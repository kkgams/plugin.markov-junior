package markov_junior

import xml "core:encoding/xml"
import "core:fmt"
import "core:os"
import "core:strings"

Named_Tile_Data :: struct {name: string, start, count: int}

wfc_load_tile :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid, parent_symmetry: string) -> WFC_State {
	w := WFC_State{counter = -1, tile_mode = true, n = 1}
	w.periodic = xml_attr_bool(doc, id, "periodic")
	w.shannon = xml_attr_bool(doc, id, "shannon")
	w.tries = xml_attr_int(doc, id, "tries", 1000)
	name := xml_attr(doc, id, "tileset")
	tilesname := xml_attr(doc, id, "tiles", name)
	w.overlap = xml_attr_int(doc, id, "overlap", 0)
	w.overlapz = xml_attr_int(doc, id, "overlapz", 0)

	tdoc, err := xml.load_from_file(fmt.tprintf("resources/tilesets/%s.xml", name))
	if err != .None || tdoc == nil do return w
	defer xml.destroy(tdoc)
	root := xml.Element_ID(0)
	full := xml_attr_bool(tdoc, root, "fullSymmetry")

	first_tile := xml.Element_ID(0)
	tiles_parent := xml.Element_ID(0)
	neighbors_parent := xml.Element_ID(0)
	for value in tdoc.elements[root].value { #partial switch cid in value { case xml.Element_ID:
		if tdoc.elements[cid].ident == "tiles" { tiles_parent = cid }
		if tdoc.elements[cid].ident == "neighbors" { neighbors_parent = cid }
	}}
	for value in tdoc.elements[tiles_parent].value { #partial switch cid in value { case xml.Element_ID:
		if tdoc.elements[cid].ident == "tile" { first_tile = cid; break }
	}}
	first_name := xml_attr(tdoc, first_tile, "name")
	first, sx, sy, sz := tile_load_vox_ints(fmt.tprintf("resources/tilesets/%s/%s.vox", tilesname, first_name))
	if first != nil do delete(first)
	if sx <= 0 || sx != sy do return w
	if full && sx != sz do return w
	w.tile_s = sx; w.tile_sz = sz
	w.newgrid = grid_init((sx - w.overlap) * g.mx + w.overlap, (sx - w.overlap) * g.my + w.overlap, (sz - w.overlapz) * g.mz + w.overlapz, xml_attr(doc, id, "values"), false)
	w.newgrid.folder = xml_attr(doc, id, "folder", g.folder)
	load_unions(doc, id, &w.newgrid)

	uniques := make([dynamic]int)
	defer delete(uniques)
	named := make([dynamic]Named_Tile_Data)
	defer delete(named)
	pats := make([dynamic][]u8)
	defer delete(pats)
	weights_dyn := make([dynamic]f64)
	defer delete(weights_dyn)
	for value in tdoc.elements[tiles_parent].value { #partial switch tid in value { case xml.Element_ID:
		if tdoc.elements[tid].ident != "tile" do continue
		tname := xml_attr(tdoc, tid, "name")
		weight := xml_attr_f64(tdoc, tid, "weight", 1.0)
		vox, vx, vy, vz := tile_load_vox_ints(fmt.tprintf("resources/tilesets/%s/%s.vox", tilesname, tname))
		if vox == nil || vx != sx || vy != sx || vz != sz { if vox != nil do delete(vox); continue }
		flat := tile_ords(vox, &uniques)
		delete(vox)
		start := len(pats)
		locals := tile_square_symmetries(flat, sx, sz)
		if full { delete(locals); locals = tile_cube_symmetries(flat, sx, sz) }
		delete(flat)
		for p in locals {
			append(&pats, p)
			append(&weights_dyn, weight)
		}
		append(&named, Named_Tile_Data{tname, start, len(locals)})
		delete(locals)
	}}
	w.p = len(pats)
	w.patterns = make([][]u8, len(pats)); copy(w.patterns, pats[:])
	w.weights = make([]f64, len(weights_dyn)); copy(w.weights, weights_dyn[:])
	if w.p == 0 do return w

	temp := make([]bool, 6 * w.p * w.p)
	defer delete(temp)
	setprop :: proc(temp: []bool, p: int, d, a, b: int) { if a >= 0 && b >= 0 do temp[(d * p + a) * p + b] = true }
	for value in tdoc.elements[neighbors_parent].value { #partial switch nid in value { case xml.Element_ID:
		if tdoc.elements[nid].ident != "neighbor" do continue
		left := xml_attr(tdoc, nid, "left", "")
		right := xml_attr(tdoc, nid, "right", "")
		if left != "" && full {
			lt := tile_from_attr(left, named[:], w.patterns, sx, sz)
			rt := tile_from_attr(right, named[:], w.patterns, sx, sz)
			lsym := tile_square_symmetries_rf(lt, sx, sz, tile_x_rotate, tile_y_reflect)
			rsym := tile_square_symmetries_rf(rt, sx, sz, tile_x_rotate, tile_y_reflect)
			for i in 0..<len(lsym) { setprop(temp, w.p, 0, tile_index(w.patterns, lsym[i]), tile_index(w.patterns, rsym[i])); setprop(temp, w.p, 0, tile_index(w.patterns, tile_x_reflect(rsym[i], sx, sz)), tile_index(w.patterns, tile_x_reflect(lsym[i], sx, sz))) }
			dt := tile_z_rotate(lt, sx, sz); ut := tile_z_rotate(rt, sx, sz)
			dsym := tile_square_symmetries_rf(dt, sx, sz, tile_y_rotate, tile_z_reflect)
			usym := tile_square_symmetries_rf(ut, sx, sz, tile_y_rotate, tile_z_reflect)
			for i in 0..<len(dsym) { setprop(temp, w.p, 1, tile_index(w.patterns, dsym[i]), tile_index(w.patterns, usym[i])); setprop(temp, w.p, 1, tile_index(w.patterns, tile_y_reflect(usym[i], sx, sz)), tile_index(w.patterns, tile_y_reflect(dsym[i], sx, sz))) }
			bt := tile_y_rotate(lt, sx, sz); tt := tile_y_rotate(rt, sx, sz)
			bsym := tile_square_symmetries_rf(bt, sx, sz, tile_z_rotate, tile_x_reflect)
			tsym := tile_square_symmetries_rf(tt, sx, sz, tile_z_rotate, tile_x_reflect)
			for i in 0..<len(bsym) { setprop(temp, w.p, 4, tile_index(w.patterns, bsym[i]), tile_index(w.patterns, tsym[i])); setprop(temp, w.p, 4, tile_index(w.patterns, tile_z_reflect(tsym[i], sx, sz)), tile_index(w.patterns, tile_z_reflect(bsym[i], sx, sz))) }
		} else if left != "" {
			lt := tile_from_attr(left, named[:], w.patterns, sx, sz)
			rt := tile_from_attr(right, named[:], w.patterns, sx, sz)
			li := tile_index(w.patterns, lt); ri := tile_index(w.patterns, rt)
			setprop(temp, w.p, 0, li, ri)
			setprop(temp, w.p, 0, tile_index(w.patterns, tile_y_reflect(lt, sx, sz)), tile_index(w.patterns, tile_y_reflect(rt, sx, sz)))
			setprop(temp, w.p, 0, tile_index(w.patterns, tile_x_reflect(rt, sx, sz)), tile_index(w.patterns, tile_x_reflect(lt, sx, sz)))
			setprop(temp, w.p, 0, tile_index(w.patterns, tile_y_reflect(tile_x_reflect(rt, sx, sz), sx, sz)), tile_index(w.patterns, tile_y_reflect(tile_x_reflect(lt, sx, sz), sx, sz)))
			dt := tile_z_rotate(lt, sx, sz); ut := tile_z_rotate(rt, sx, sz)
			setprop(temp, w.p, 1, tile_index(w.patterns, dt), tile_index(w.patterns, ut))
			setprop(temp, w.p, 1, tile_index(w.patterns, tile_x_reflect(dt, sx, sz)), tile_index(w.patterns, tile_x_reflect(ut, sx, sz)))
			setprop(temp, w.p, 1, tile_index(w.patterns, tile_y_reflect(ut, sx, sz)), tile_index(w.patterns, tile_y_reflect(dt, sx, sz)))
			setprop(temp, w.p, 1, tile_index(w.patterns, tile_x_reflect(tile_y_reflect(ut, sx, sz), sx, sz)), tile_index(w.patterns, tile_x_reflect(tile_y_reflect(dt, sx, sz), sx, sz)))
		} else {
			top := xml_attr(tdoc, nid, "top", ""); bottom := xml_attr(tdoc, nid, "bottom", "")
			tt := tile_from_attr(top, named[:], w.patterns, sx, sz); bt := tile_from_attr(bottom, named[:], w.patterns, sx, sz)
			tsym := tile_square_symmetries_no_unique(tt, sx, sz); bsym := tile_square_symmetries_no_unique(bt, sx, sz)
			for i in 0..<len(tsym) do setprop(temp, w.p, 4, tile_index(w.patterns, bsym[i]), tile_index(w.patterns, tsym[i]))
			for i in 0..<len(tsym) { delete(tsym[i]); delete(bsym[i]) }
			delete(tsym); delete(bsym)
		}
	}}
	for p2 in 0..<w.p do for p1 in 0..<w.p {
		temp[(2 * w.p + p2) * w.p + p1] = temp[(0 * w.p + p1) * w.p + p2]
		temp[(3 * w.p + p2) * w.p + p1] = temp[(1 * w.p + p1) * w.p + p2]
		temp[(5 * w.p + p2) * w.p + p1] = temp[(4 * w.p + p1) * w.p + p2]
	}
	w.propagator = make([][][]int, 6)
	for d in 0..<6 { w.propagator[d] = make([][]int, w.p); for p1 in 0..<w.p {
		list := make([dynamic]int)
		for p2 in 0..<w.p do if temp[(d * w.p + p1) * w.p + p2] do append(&list, p2)
		w.propagator[d][p1] = make([]int, len(list)); copy(w.propagator[d][p1], list[:]); delete(list)
	}}

	for value in doc.elements[id].value { #partial switch rid in value { case xml.Element_ID:
		if doc.elements[rid].ident == "rule" {
			input := grid_value(g, xml_attr(doc, rid, "in")[0])
			outs := strings.split(xml_attr(doc, rid, "out"), "|")
			pos := make([]bool, w.p)
			for out in outs { for nt in named { if nt.name == out { for p := nt.start; p < nt.start + nt.count; p += 1 do pos[p] = true } } }
			delete(outs)
			append(&w.map_values, input); append(&w.map_positions, pos)
		}
	}}
	if wfc_map_get(&w, 0) == nil { pos := make([]bool, w.p); for i in 0..<w.p do pos[i] = true; append(&w.map_values, 0); append(&w.map_positions, pos) }
	wfc_base_finish(&w, g)
	return w
}

// VOX loader matching source/VoxHelper.cs: sparse voxel color indices, empty = -1.
tile_load_vox_ints :: proc(path: string) -> ([]int, int, int, int) {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != os.ERROR_NONE do return nil, -1, -1, -1
	defer delete(data)
	mx, my, mz := -1, -1, -1
	result: []int
	off := 8
	for off + 12 <= len(data) {
		id := string(data[off:off+4])
		size := le_i32(data, off+4)
		off += 12
		if id == "SIZE" && off + 12 <= len(data) { mx = le_i32(data, off); my = le_i32(data, off+4); mz = le_i32(data, off+8) }
		if id == "XYZI" && mx > 0 { result = make([]int, mx*my*mz); for i in 0..<len(result) do result[i] = -1; n := le_i32(data, off); p := off + 4; for _ in 0..<n { x:=int(data[p]); y:=int(data[p+1]); z:=int(data[p+2]); c:=int(data[p+3]); result[x+y*mx+z*mx*my]=c; p+=4 } }
		off += size
	}
	return result, mx, my, mz
}

tile_ords :: proc(data: []int, uniques: ^[dynamic]int) -> []u8 { r:=make([]u8,len(data)); for d,i in data { ord:=-1; for u,j in uniques do if u==d {ord=j; break}; if ord<0 {ord=len(uniques); append(uniques,d)}; r[i]=u8(ord)}; return r }

tile_z_rotate :: proc(p: []u8, s, sz: int) -> []u8 { q:=make([]u8,len(p)); for z in 0..<sz do for y in 0..<s do for x in 0..<s do q[x+y*s+z*s*s]=p[y+(s-1-x)*s+z*s*s]; return q }
tile_y_rotate :: proc(p: []u8, s, sz: int) -> []u8 { q:=make([]u8,len(p)); for z in 0..<sz do for y in 0..<s do for x in 0..<s do q[x+y*s+z*s*s]=p[z+y*s+(s-1-x)*s*s]; return q }
tile_x_rotate :: proc(p: []u8, s, sz: int) -> []u8 { q:=make([]u8,len(p)); for z in 0..<s do for y in 0..<sz do for x in 0..<s do q[x+y*s+z*s*sz]=p[x+z*s+(s-1-y)*s*s]; return q }
tile_x_reflect :: proc(p: []u8, s, sz: int) -> []u8 { q:=make([]u8,len(p)); for z in 0..<sz do for y in 0..<s do for x in 0..<s do q[x+y*s+z*s*s]=p[(s-1-x)+y*s+z*s*s]; return q }
tile_y_reflect :: proc(p: []u8, s, sz: int) -> []u8 { q:=make([]u8,len(p)); for z in 0..<sz do for y in 0..<s do for x in 0..<s do q[x+y*s+z*s*s]=p[x+(s-1-y)*s+z*s*s]; return q }
tile_z_reflect :: proc(p: []u8, s, sz: int) -> []u8 { q:=make([]u8,len(p)); for z in 0..<sz do for y in 0..<s do for x in 0..<s do q[x+y*s+z*s*s]=p[x+y*s+(sz-1-z)*s*s]; return q }

tile_same :: proc(a,b: []u8)->bool{if len(a)!=len(b) do return false; for i in 0..<len(a) do if a[i]!=b[i] do return false; return true}
tile_index :: proc(list: [][]u8, p: []u8)->int{for i in 0..<len(list) do if tile_same(list[i],p) do return i; return -1}

tile_square_symmetries :: proc(base: []u8, s, sz: int) -> []([]u8) { all:=tile_square_symmetries_no_unique(base,s,sz); res:=make([dynamic][]u8); for p in all { dup:=false; for q in res do if tile_same(q,p){dup=true;break}; if dup {delete(p)} else {append(&res,p)} }; delete(all); out:=make([][]u8,len(res)); copy(out,res[:]); delete(res); return out }
tile_square_symmetries_no_unique :: proc(base: []u8, s, sz: int) -> []([]u8) { return tile_square_symmetries_rf(base, s, sz, tile_z_rotate, tile_x_reflect) }
tile_square_symmetries_rf :: proc(base: []u8, s, sz: int, rot: proc([]u8,int,int)->[]u8, refl: proc([]u8,int,int)->[]u8) -> []([]u8) { arr:=make([][]u8,8); arr[0]=make([]u8,len(base)); copy(arr[0],base); arr[1]=refl(arr[0],s,sz); arr[2]=rot(arr[0],s,sz); arr[3]=refl(arr[2],s,sz); arr[4]=rot(arr[2],s,sz); arr[5]=refl(arr[4],s,sz); arr[6]=rot(arr[4],s,sz); arr[7]=refl(arr[6],s,sz); return arr }

tile_cube_symmetries :: proc(base: []u8, s, sz: int) -> []([]u8) { arr:=make([][]u8,48); arr[0]=make([]u8,len(base)); copy(arr[0],base); arr[1]=tile_x_reflect(arr[0],s,sz); arr[2]=tile_z_rotate(arr[0],s,sz); arr[3]=tile_x_reflect(arr[2],s,sz); arr[4]=tile_z_rotate(arr[2],s,sz); arr[5]=tile_x_reflect(arr[4],s,sz); arr[6]=tile_z_rotate(arr[4],s,sz); arr[7]=tile_x_reflect(arr[6],s,sz); arr[8]=tile_y_rotate(arr[0],s,sz); arr[9]=tile_x_reflect(arr[8],s,sz); arr[10]=tile_y_rotate(arr[2],s,sz); arr[11]=tile_x_reflect(arr[10],s,sz); arr[12]=tile_y_rotate(arr[4],s,sz); arr[13]=tile_x_reflect(arr[12],s,sz); arr[14]=tile_y_rotate(arr[6],s,sz); arr[15]=tile_x_reflect(arr[14],s,sz); arr[16]=tile_y_rotate(arr[8],s,sz); arr[17]=tile_x_reflect(arr[16],s,sz); arr[18]=tile_y_rotate(arr[10],s,sz); arr[19]=tile_x_reflect(arr[18],s,sz); arr[20]=tile_y_rotate(arr[12],s,sz); arr[21]=tile_x_reflect(arr[20],s,sz); arr[22]=tile_y_rotate(arr[14],s,sz); arr[23]=tile_x_reflect(arr[22],s,sz); arr[24]=tile_y_rotate(arr[16],s,sz); arr[25]=tile_x_reflect(arr[24],s,sz); arr[26]=tile_y_rotate(arr[18],s,sz); arr[27]=tile_x_reflect(arr[26],s,sz); arr[28]=tile_y_rotate(arr[20],s,sz); arr[29]=tile_x_reflect(arr[28],s,sz); arr[30]=tile_y_rotate(arr[22],s,sz); arr[31]=tile_x_reflect(arr[30],s,sz); arr[32]=tile_z_rotate(arr[8],s,sz); arr[33]=tile_x_reflect(arr[32],s,sz); arr[34]=tile_z_rotate(arr[10],s,sz); arr[35]=tile_x_reflect(arr[34],s,sz); arr[36]=tile_z_rotate(arr[12],s,sz); arr[37]=tile_x_reflect(arr[36],s,sz); arr[38]=tile_z_rotate(arr[14],s,sz); arr[39]=tile_x_reflect(arr[38],s,sz); arr[40]=tile_z_rotate(arr[24],s,sz); arr[41]=tile_x_reflect(arr[40],s,sz); arr[42]=tile_z_rotate(arr[26],s,sz); arr[43]=tile_x_reflect(arr[42],s,sz); arr[44]=tile_z_rotate(arr[28],s,sz); arr[45]=tile_x_reflect(arr[44],s,sz); arr[46]=tile_z_rotate(arr[30],s,sz); arr[47]=tile_x_reflect(arr[46],s,sz); res:=make([dynamic][]u8); for p in arr { dup:=false; for q in res do if tile_same(q,p){dup=true;break}; if dup {delete(p)} else {append(&res,p)} }; delete(arr); out:=make([][]u8,len(res)); copy(out,res[:]); delete(res); return out }

tile_from_attr :: proc(attr: string, named: []Named_Tile_Data, patterns: [][]u8, s, sz: int) -> []u8 { parts:=strings.split(attr," "); defer delete(parts); action:=""; name:=attr; if len(parts)==2 { action=parts[0]; name=parts[1] }; idx:=0; for nt in named do if nt.name==name {idx=nt.start; break}; p:=make([]u8,len(patterns[idx])); copy(p,patterns[idx]); for i:=len(action)-1; i>=0; i-=1 { ch:=action[i]; old:=p; if ch=='z' { p=tile_z_rotate(old,s,sz); delete(old) } else if ch=='y' { p=tile_y_rotate(old,s,sz); delete(old) } else if ch=='x' { p=tile_x_rotate(old,s,sz); delete(old) } }; return p }

wfc_tile_update :: proc(w: ^WFC_State, g: ^Grid, random: ^MJRandom) {
	wfc_tile_update_to(w, g, g.mx, g.my, g.mz, random)
}

wfc_tile_update_to :: proc(w: ^WFC_State, out: ^Grid, cmx, cmy, cmz: int, random: ^MJRandom) {
	r := mj_random_init(mj_random_next(random))
	for z in 0..<cmz do for y in 0..<cmy do for x in 0..<cmx {
		i := x+y*cmx+z*cmx*cmy
		votes := make([]int, w.tile_s*w.tile_s*w.tile_sz*len(out.characters)); defer delete(votes)
		for t in 0..<w.p do if w.wave.data[i*w.p+t] { tile:=w.patterns[t]; for dz in 0..<w.tile_sz do for dy in 0..<w.tile_s do for dx in 0..<w.tile_s { di:=dx+dy*w.tile_s+dz*w.tile_s*w.tile_s; votes[di*len(out.characters)+int(tile[di])] += 1 } }
		for dz in 0..<w.tile_sz do for dy in 0..<w.tile_s do for dx in 0..<w.tile_s { di:=dx+dy*w.tile_s+dz*w.tile_s*w.tile_s; max:=-1.0; arg:u8=0xff; for c in 0..<len(out.characters){v:=f64(votes[di*len(out.characters)+c])+0.1*mj_random_next_f64(&r); if v>max {max=v; arg=u8(c)}}; sx:=x*(w.tile_s-w.overlap)+dx; sy:=y*(w.tile_s-w.overlap)+dy; sz:=z*(w.tile_sz-w.overlapz)+dz; out.state[sx+sy*out.mx+sz*out.mx*out.my]=arg }
	}
}
