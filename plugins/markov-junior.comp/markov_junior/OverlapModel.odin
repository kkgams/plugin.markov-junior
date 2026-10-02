package markov_junior

import png "core:image/png"
import "core:fmt"
import xml "core:encoding/xml"

wfc_load_overlap :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid, parent_symmetry: string) -> WFC_State {
	w := WFC_State{counter = -1}
	w.n = xml_attr_int(doc, id, "n", 3)
	w.periodic = true
	w.shannon = xml_attr_bool(doc, id, "shannon")
	w.tries = xml_attr_int(doc, id, "tries", 1000)
	w.newgrid = grid_init(g.mx, g.my, g.mz, xml_attr(doc, id, "values"), false)
	w.newgrid.folder = xml_attr(doc, id, "folder", g.folder)
	load_unions(doc, id, &w.newgrid)
	symmetry := xml_attr(doc, id, "symmetry", parent_symmetry)
	periodic_input := xml_attr_bool(doc, id, "periodicInput", true)

	name := xml_attr(doc, id, "sample")
	img, err := png.load(fmt.tprintf("resources/samples/%s.png", name))
	if err != nil || img == nil do return w
	defer png.destroy(img)
	smx := img.width; smy := img.height
	sample := make([]u8, smx * smy)
	defer delete(sample)
	uniques := make([dynamic]u32)
	defer delete(uniques)
	pix := img.pixels.buf[:]; channels := img.channels
	for y in 0..<smy do for x in 0..<smx {
		i := (x + y * smx) * channels
		color: u32 = 0
		if channels >= 3 {
			a: u32 = 0xff
			if channels >= 4 do a = u32(pix[i + 3])
			color = (a << 24) | (u32(pix[i]) << 16) | (u32(pix[i + 1]) << 8) | u32(pix[i + 2])
		} else if channels == 1 {
			v := u32(pix[i])
			color = 0xff000000 | (v << 16) | (v << 8) | v
		}
		sample[x + y * smx] = u8(resource_ord(&uniques, color))
	}
	c_count := len(uniques)

	keys := make([dynamic]int)
	counts := make([dynamic]f64)
	ordering := make([dynamic]int)
	defer { delete(keys); delete(counts); delete(ordering) }
	ymax := g.my; xmax := g.mx
	if !periodic_input { ymax = g.my - w.n + 1; xmax = g.mx - w.n + 1 }
	for y in 0..<ymax do for x in 0..<xmax {
		base := overlap_sample_pattern(sample, smx, smy, x, y, w.n)
		patterns: [8][]u8
		patterns[0] = base
		patterns[1] = overlap_reflected(patterns[0], w.n)
		patterns[2] = overlap_rotated(patterns[0], w.n)
		patterns[3] = overlap_reflected(patterns[2], w.n)
		patterns[4] = overlap_rotated(patterns[2], w.n)
		patterns[5] = overlap_reflected(patterns[4], w.n)
		patterns[6] = overlap_rotated(patterns[4], w.n)
		patterns[7] = overlap_reflected(patterns[6], w.n)
		for i in 0..<8 {
			if !square_symmetry_enabled(symmetry, i) { delete(patterns[i]); patterns[i] = nil; continue }
			ind := overlap_pattern_index(patterns[i], c_count)
			found := -1
			for k in 0..<len(keys) do if keys[k] == ind { found = k; break }
			if found >= 0 { counts[found] += 1 } else { append(&keys, ind); append(&counts, 1); append(&ordering, ind) }
		}
		for i in 0..<8 do if patterns[i] != nil do delete(patterns[i])
	}
	w.p = len(ordering)
	w.patterns = make([][]u8, w.p)
	w.weights = make([]f64, w.p)
	for idx in 0..<len(ordering) {
		w.patterns[idx] = overlap_pattern_from_index(ordering[idx], c_count, w.n)
		for k in 0..<len(keys) do if keys[k] == ordering[idx] { w.weights[idx] = counts[k]; break }
	}

	w.propagator = make([][][]int, 4)
	dxs := [?]int{1, 0, -1, 0}
	dys := [?]int{0, 1, 0, -1}
	for d in 0..<4 {
		w.propagator[d] = make([][]int, w.p)
		for t in 0..<w.p {
			list := make([dynamic]int)
			for t2 in 0..<w.p do if overlap_agrees(w.patterns[t], w.patterns[t2], dxs[d], dys[d], w.n) do append(&list, t2)
			w.propagator[d][t] = make([]int, len(list)); copy(w.propagator[d][t], list[:]); delete(list)
		}
	}

	for value in doc.elements[id].value {
		#partial switch child_id in value {
		case xml.Element_ID:
			if doc.elements[child_id].ident == "rule" {
				input := grid_value(g, xml_attr(doc, child_id, "in")[0])
				outs := split_outputs_values(xml_attr(doc, child_id, "out"), &w.newgrid)
				pos := make([]bool, w.p)
				for t in 0..<w.p do for o in outs do if w.patterns[t][0] == o do pos[t] = true
				append(&w.map_values, input); append(&w.map_positions, pos)
				delete(outs)
			}
		}
	}
	if wfc_map_get(&w, 0) == nil {
		pos := make([]bool, w.p); for i in 0..<w.p do pos[i] = true
		append(&w.map_values, 0); append(&w.map_positions, pos)
	}
	wfc_base_finish(&w, g)
	return w
}

split_outputs_values :: proc(s: string, g: ^Grid) -> []u8 {
	parts := strings_split_bar(s)
	out := make([]u8, len(parts))
	for i in 0..<len(parts) do out[i] = grid_value(g, parts[i][0])
	delete(parts)
	return out
}

strings_split_bar :: proc(s: string) -> []string {
	parts_dyn := make([dynamic]string)
	start := 0
	for ch, i in s do if ch == '|' { append(&parts_dyn, s[start:i]); start = i + 1 }
	append(&parts_dyn, s[start:])
	parts := make([]string, len(parts_dyn))
	copy(parts, parts_dyn[:])
	delete(parts_dyn)
	return parts
}

overlap_sample_pattern :: proc(sample: []u8, smx, smy, x, y, n: int) -> []u8 {
	p := make([]u8, n * n)
	for dy in 0..<n do for dx in 0..<n do p[dx + dy * n] = sample[(x + dx) % smx + ((y + dy) % smy) * smx]
	return p
}

overlap_rotated :: proc(p: []u8, n: int) -> []u8 { q := make([]u8, n*n); for y in 0..<n do for x in 0..<n do q[x+y*n] = p[n-1-y+x*n]; return q }
overlap_reflected :: proc(p: []u8, n: int) -> []u8 { q := make([]u8, n*n); for y in 0..<n do for x in 0..<n do q[x+y*n] = p[n-1-x+y*n]; return q }

overlap_pattern_index :: proc(p: []u8, c: int) -> int { result := 0; power := 1; for i in 0..<len(p) { result += int(p[len(p)-1-i]) * power; power *= c }; return result }

overlap_pattern_from_index :: proc(ind, c, n: int) -> []u8 {
	residue := ind; power := 1; for i in 0..<n*n do power *= c
	result := make([]u8, n*n)
	for i in 0..<len(result) { power /= c; count := 0; for residue >= power { residue -= power; count += 1 }; result[i] = u8(count) }
	return result
}

overlap_agrees :: proc(p1, p2: []u8, dx, dy, n: int) -> bool {
	xmin := 0; xmax := n; ymin := 0; ymax := n
	if dx < 0 { xmax = dx + n } else { xmin = dx }
	if dy < 0 { ymax = dy + n } else { ymin = dy }
	for y in ymin..<ymax do for x in xmin..<xmax do if p1[x+n*y] != p2[x-dx+n*(y-dy)] do return false
	return true
}

wfc_overlap_update :: proc(w: ^WFC_State, g: ^Grid, random: ^MJRandom) {
	mx := g.mx; my := g.my
	votes := make([]int, len(g.state) * len(g.characters)); defer delete(votes)
	for i in 0..<w.wave.length {
		x := i % mx; y := i / mx
		for p in 0..<w.p do if w.wave.data[i*w.p+p] {
			pattern := w.patterns[p]
			for dy in 0..<w.n {
				ydy := y + dy; if ydy >= my do ydy -= my
				for dx in 0..<w.n {
					xdx := x + dx; if xdx >= mx do xdx -= mx
					value := pattern[dx + dy*w.n]
					votes[(xdx + ydy*mx)*len(g.characters)+int(value)] += 1
				}
			}
		}
	}
	r := mj_random_init(mj_random_next(random))
	for i in 0..<len(g.state) {
		max := -1.0; arg: u8 = 0xff
		for c in 0..<len(g.characters) {
			value := f64(votes[i*len(g.characters)+c]) + 0.1 * mj_random_next_f64(&r)
			if value > max { arg = u8(c); max = value }
		}
		g.state[i] = arg
	}
}
