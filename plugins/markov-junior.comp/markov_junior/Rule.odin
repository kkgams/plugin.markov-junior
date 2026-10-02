package markov_junior

import "core:strings"
import "core:fmt"
import "core:os"
import "core:image/png"

Shift :: struct {
	x, y, z: int,
}

Rule :: struct {
	imx, imy, imz: int,
	omx, omy, omz: int,
	input:         []i32,
	output:        []u8,
	ishifts:       [][]Shift,
	oshifts:       [][]Shift,
	binput:        []u8,
	p:             f64,
}

Pattern :: struct {
	data: []u8,
	mx, my, mz: int,
}

rule_destroy :: proc(r: ^Rule) {
	if r.input != nil do delete(r.input)
	if r.output != nil do delete(r.output)
	for i in 0..<len(r.ishifts) {
		if r.ishifts[i] != nil do delete(r.ishifts[i])
	}
	if r.ishifts != nil do delete(r.ishifts)
	for i in 0..<len(r.oshifts) {
		if r.oshifts[i] != nil do delete(r.oshifts[i])
	}
	if r.oshifts != nil do delete(r.oshifts)
	if r.binput != nil do delete(r.binput)
}

parse_pattern :: proc(s: string) -> Pattern {
	layers := strings.split(s, " ")
	defer delete(layers)
	rows0 := strings.split(layers[0], "/")
	mx := len(rows0[0])
	my := len(rows0)
	delete(rows0)
	mz := len(layers)

	p := Pattern{data = make([]u8, mx * my * mz), mx = mx, my = my, mz = mz}
	for z in 0..<mz {
		layer := layers[mz - 1 - z]
		rows := strings.split(layer, "/")
		for y in 0..<my {
			row := rows[y]
			for x in 0..<mx {
				p.data[x + y * mx + z * mx * my] = row[x]
			}
		}
		delete(rows)
	}
	return p
}

pattern_destroy :: proc(p: ^Pattern) {
	if p.data != nil do delete(p.data)
}


resource_path :: proc(g: ^Grid, name: string) -> string {
	if len(g.folder) > 0 {
		if g.mz == 1 do return fmt.tprintf("resources/rules/%s/%s.png", g.folder, name)
		return fmt.tprintf("resources/rules/%s/%s.vox", g.folder, name)
	}
	if g.mz == 1 do return fmt.tprintf("resources/rules/%s.png", name)
	return fmt.tprintf("resources/rules/%s.vox", name)
}

rule_init_mixed :: proc(g: ^Grid, in_string, out_string, fin, fout, file, legend: string, probability := 1.0) -> Rule {
	return rule_init_mixed_grids(g, g, in_string, out_string, fin, fout, file, legend, probability)
}

rule_init_mixed_grids :: proc(gin, gout: ^Grid, in_string, out_string, fin, fout, file, legend: string, probability := 1.0) -> Rule {
	if file != "" {
		p := load_resource_pattern(gout, file, legend)
		defer pattern_destroy(&p)
		half := p.mx / 2
		input_chars := make([]u8, half * p.my * p.mz)
		output_chars := make([]u8, half * p.my * p.mz)
		for z in 0..<p.mz do for y in 0..<p.my do for x in 0..<half {
			input_chars[x + y * half + z * half * p.my] = p.data[x + y * p.mx + z * p.mx * p.my]
			output_chars[x + y * half + z * half * p.my] = p.data[x + half + y * p.mx + z * p.mx * p.my]
		}
		return rule_from_char_arrays_grids(gin, gout, input_chars, half, p.my, p.mz, output_chars, half, p.my, p.mz, probability)
	}

	pin: Pattern
	pout: Pattern
	if in_string != "" {
		pin = parse_pattern(in_string)
	} else {
		pin = load_resource_pattern(gin, fin, legend)
	}
	defer pattern_destroy(&pin)
	if out_string != "" {
		pout = parse_pattern(out_string)
	} else {
		pout = load_resource_pattern(gout, fout, legend)
	}
	defer pattern_destroy(&pout)
	return rule_from_char_arrays_grids(gin, gout, pin.data, pin.mx, pin.my, pin.mz, pout.data, pout.mx, pout.my, pout.mz, probability)
}

rule_from_char_arrays :: proc(g: ^Grid, in_chars: []u8, imx, imy, imz: int, out_chars: []u8, omx, omy, omz: int, probability := 1.0) -> Rule {
	return rule_from_char_arrays_grids(g, g, in_chars, imx, imy, imz, out_chars, omx, omy, omz, probability)
}

rule_input_symbol_known :: proc(g: ^Grid, ch: u8) -> bool {
	if ch == '*' do return true
	if grid_value(g, ch) != 0xff do return true
	for i in 0..<len(g.union_keys) do if g.union_keys[i] == ch do return true
	return false
}

rule_from_char_arrays_grids :: proc(gin, gout: ^Grid, in_chars: []u8, imx, imy, imz: int, out_chars: []u8, omx, omy, omz: int, probability := 1.0) -> Rule {
	for ch in in_chars do if !rule_input_symbol_known(gin, ch) do return {}
	for ch in out_chars do if ch != '*' && grid_value(gout, ch) == 0xff do return {}
	input := make([]i32, len(in_chars))
	output := make([]u8, len(out_chars))
	for i in 0..<len(in_chars) do input[i] = grid_wave(gin, in_chars[i])
	for i in 0..<len(out_chars) {
		ch := out_chars[i]
		if ch == '*' {
			output[i] = 0xff
		} else {
			output[i] = grid_value(gout, ch)
		}
	}
	return rule_from_arrays(gout, input, imx, imy, imz, output, omx, omy, omz, probability)
}

load_resource_pattern :: proc(g: ^Grid, name, legend: string) -> Pattern {
	if g.mz == 1 do return load_png_pattern(resource_path(g, name), legend)
	return load_vox_pattern(resource_path(g, name), legend)
}

load_png_pattern :: proc(path, legend: string) -> Pattern {
	img, err := png.load(path)
	if err != nil || img == nil {
		return {}
	}
	defer png.destroy(img)
	p := Pattern{data = make([]u8, img.width * img.height), mx = img.width, my = img.height, mz = 1}
	uniques := make([dynamic]u32)
	defer delete(uniques)
	pixels := img.pixels.buf[:]
	channels := img.channels
	for y in 0..<img.height {
		for x in 0..<img.width {
			i := (x + y * img.width) * channels
			color: u32 = 0
			if channels >= 3 {
				a: u32 = 0xff
				if channels >= 4 do a = u32(pixels[i + 3])
				// Match C# ImageSharp Bgra32 copied to int: AARRGGBB.
				color = (a << 24) | (u32(pixels[i]) << 16) | (u32(pixels[i + 1]) << 8) | u32(pixels[i + 2])
			} else if channels == 1 {
				v := u32(pixels[i])
				color = 0xff000000 | (v << 16) | (v << 8) | v
			}
			ord := resource_ord(&uniques, color)
			p.data[x + y * img.width] = legend[ord]
		}
	}
	return p
}

resource_ord :: proc(uniques: ^[dynamic]u32, color: u32) -> int {
	for i in 0..<len(uniques) {
		if uniques[i] == color do return i
	}
	append(uniques, color)
	return len(uniques) - 1
}

le_i32 :: proc(data: []u8, off: int) -> int {
	return int(data[off]) | (int(data[off + 1]) << 8) | (int(data[off + 2]) << 16) | (int(data[off + 3]) << 24)
}

load_vox_pattern :: proc(path, legend: string) -> Pattern {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != os.ERROR_NONE do return {}
	defer delete(data)
	mx, my, mz := -1, -1, -1
	colors: []i32
	defer if colors != nil do delete(colors)
	off := 8
	for off + 12 <= len(data) {
		id := string(data[off:off + 4])
		chunk_size := le_i32(data, off + 4)
		_ = le_i32(data, off + 8)
		off += 12
		if id == "SIZE" && off + 12 <= len(data) {
			mx = le_i32(data, off)
			my = le_i32(data, off + 4)
			mz = le_i32(data, off + 8)
		} else if id == "XYZI" && mx > 0 && my > 0 && mz > 0 && off + 4 <= len(data) {
			colors = make([]i32, mx * my * mz)
			for i in 0..<len(colors) do colors[i] = -1
			n := le_i32(data, off)
			pos := off + 4
			for i in 0..<n {
				x := int(data[pos]); y := int(data[pos + 1]); z := int(data[pos + 2]); c := i32(data[pos + 3]); pos += 4
				colors[x + y * mx + z * mx * my] = c
			}
		}
		off += chunk_size
	}
	if colors == nil do return {}
	p := Pattern{data = make([]u8, mx * my * mz), mx = mx, my = my, mz = mz}
	uniques := make([dynamic]u32)
	defer delete(uniques)
	for i in 0..<len(colors) {
		ord := resource_ord(&uniques, u32(colors[i]))
		p.data[i] = legend[ord]
	}
	return p
}

rule_init :: proc(g: ^Grid, in_string, out_string: string, probability := 1.0) -> Rule {
	pin := parse_pattern(in_string)
	defer pattern_destroy(&pin)
	pout := parse_pattern(out_string)
	defer pattern_destroy(&pout)

	input := make([]i32, len(pin.data))
	output := make([]u8, len(pout.data))

	for i in 0..<len(pin.data) {
		input[i] = grid_wave(g, pin.data[i])
	}
	for i in 0..<len(pout.data) {
		ch := pout.data[i]
		if ch == '*' {
			output[i] = 0xff
		} else {
			output[i] = grid_value(g, ch)
		}
	}

	return rule_from_arrays(g, input, pin.mx, pin.my, pin.mz, output, pout.mx, pout.my, pout.mz, probability)
}

rule_from_arrays :: proc(g: ^Grid, input: []i32, imx, imy, imz: int, output: []u8, omx, omy, omz: int, probability := 1.0) -> Rule {
	r := Rule{
		imx = imx, imy = imy, imz = imz,
		omx = omx, omy = omy, omz = omz,
		input = input,
		output = output,
		ishifts = make([][]Shift, len(g.characters)),
		p = probability,
	}

	for c in 0..<len(g.characters) {
		list := make([dynamic]Shift)
		for z in 0..<r.imz {
			for y in 0..<r.imy {
				for x in 0..<r.imx {
					i := x + y * r.imx + z * r.imx * r.imy
					w := r.input[i]
					if (w & (i32(1) << uint(c))) != 0 {
						append(&list, Shift{x, y, z})
					}
				}
			}
		}
		r.ishifts[c] = make([]Shift, len(list))
		copy(r.ishifts[c], list[:])
		delete(list)
	}

	if omx == imx && omy == imy && omz == imz {
		r.oshifts = make([][]Shift, len(g.characters))
		for c in 0..<len(g.characters) {
			list := make([dynamic]Shift)
			for z in 0..<r.omz do for y in 0..<r.omy do for x in 0..<r.omx {
				i := x + y * r.omx + z * r.omx * r.omy
				o := r.output[i]
				if o != 0xff {
					if int(o) == c do append(&list, Shift{x, y, z})
				} else {
					append(&list, Shift{x, y, z})
				}
			}
			r.oshifts[c] = make([]Shift, len(list))
			copy(r.oshifts[c], list[:])
			delete(list)
		}
	}

	wildcard := (i32(1) << uint(len(g.characters))) - 1
	r.binput = make([]u8, len(r.input))
	for i in 0..<len(r.input) {
		w := r.input[i]
		if w == wildcard {
			r.binput[i] = 0xff
		} else {
			for c in 0..<len(g.characters) {
				if (w & (i32(1) << uint(c))) != 0 { r.binput[i] = u8(c); break }
			}
		}
	}
	return r
}

rule_clone :: proc(g: ^Grid, r: ^Rule) -> Rule {
	input := make([]i32, len(r.input))
	copy(input, r.input)
	output := make([]u8, len(r.output))
	copy(output, r.output)
	return rule_from_arrays(g, input, r.imx, r.imy, r.imz, output, r.omx, r.omy, r.omz, r.p)
}

rule_z_rotated :: proc(g: ^Grid, r: ^Rule) -> Rule {
	input := make([]i32, len(r.input))
	for z in 0..<r.imz {
		for y in 0..<r.imx {
			for x in 0..<r.imy {
				input[x + y * r.imy + z * r.imx * r.imy] = r.input[r.imx - 1 - y + x * r.imx + z * r.imx * r.imy]
			}
		}
	}

	output := make([]u8, len(r.output))
	for z in 0..<r.omz {
		for y in 0..<r.omx {
			for x in 0..<r.omy {
				output[x + y * r.omy + z * r.omx * r.omy] = r.output[r.omx - 1 - y + x * r.omx + z * r.omx * r.omy]
			}
		}
	}

	return rule_from_arrays(g, input, r.imy, r.imx, r.imz, output, r.omy, r.omx, r.omz, r.p)
}

rule_y_rotated :: proc(g: ^Grid, r: ^Rule) -> Rule {
	input := make([]i32, len(r.input))
	for z in 0..<r.imx {
		for y in 0..<r.imy {
			for x in 0..<r.imz {
				input[x + y * r.imz + z * r.imz * r.imy] = r.input[r.imx - 1 - z + y * r.imx + x * r.imx * r.imy]
			}
		}
	}

	output := make([]u8, len(r.output))
	for z in 0..<r.omx {
		for y in 0..<r.omy {
			for x in 0..<r.omz {
				output[x + y * r.omz + z * r.omz * r.omy] = r.output[r.omx - 1 - z + y * r.omx + x * r.omx * r.omy]
			}
		}
	}

	return rule_from_arrays(g, input, r.imz, r.imy, r.imx, output, r.omz, r.omy, r.omx, r.p)
}

rule_reflected :: proc(g: ^Grid, r: ^Rule) -> Rule {
	input := make([]i32, len(r.input))
	for z in 0..<r.imz {
		for y in 0..<r.imy {
			for x in 0..<r.imx {
				input[x + y * r.imx + z * r.imx * r.imy] = r.input[r.imx - 1 - x + y * r.imx + z * r.imx * r.imy]
			}
		}
	}

	output := make([]u8, len(r.output))
	for z in 0..<r.omz {
		for y in 0..<r.omy {
			for x in 0..<r.omx {
				output[x + y * r.omx + z * r.omx * r.omy] = r.output[r.omx - 1 - x + y * r.omx + z * r.omx * r.omy]
			}
		}
	}

	return rule_from_arrays(g, input, r.imx, r.imy, r.imz, output, r.omx, r.omy, r.omz, r.p)
}

rule_same :: proc(a, b: ^Rule) -> bool {
	if a.imx != b.imx || a.imy != b.imy || a.imz != b.imz || a.omx != b.omx || a.omy != b.omy || a.omz != b.omz do return false
	for i in 0..<len(a.input) {
		if a.input[i] != b.input[i] do return false
	}
	for i in 0..<len(a.output) {
		if a.output[i] != b.output[i] do return false
	}
	return true
}

append_rule_symmetries :: proc(g: ^Grid, rules: ^[dynamic]Rule, base: Rule, symmetry := "") {
	if base.imx <= 0 do return
	if g.mz == 1 {
		append_square_symmetries(g, rules, base, symmetry)
	} else {
		append_cube_symmetries(g, rules, base, symmetry)
	}
}

square_symmetry_enabled :: proc(symmetry: string, i: int) -> bool {
	if symmetry == "" || symmetry == "(xy)" do return true
	if symmetry == "()" do return i == 0
	if symmetry == "(x)" do return i == 0 || i == 1
	if symmetry == "(y)" do return i == 0 || i == 5
	if symmetry == "(x)(y)" do return i == 0 || i == 1 || i == 4 || i == 5
	if symmetry == "(xy+)" do return i == 0 || i == 2 || i == 4 || i == 6
	return true
}

append_square_symmetries :: proc(g: ^Grid, rules: ^[dynamic]Rule, base: Rule, symmetry := "") {
	things: [8]Rule
	things[0] = base
	things[1] = rule_reflected(g, &things[0])
	things[2] = rule_z_rotated(g, &things[0])
	things[3] = rule_reflected(g, &things[2])
	things[4] = rule_z_rotated(g, &things[2])
	things[5] = rule_reflected(g, &things[4])
	things[6] = rule_z_rotated(g, &things[4])
	things[7] = rule_reflected(g, &things[6])

	used: [8]bool
	for i in 0..<8 {
		if !square_symmetry_enabled(symmetry, i) {
			rule_destroy(&things[i])
			continue
		}
		duplicate := false
		for j in 0..<i {
			if used[j] && rule_same(&things[j], &things[i]) {
				duplicate = true
				break
			}
		}
		if duplicate {
			rule_destroy(&things[i])
		} else {
			used[i] = true
			append(rules, things[i])
		}
	}
}

cube_symmetry_enabled :: proc(symmetry: string, i: int) -> bool {
	if symmetry == "" || symmetry == "(xyz)" do return true
	if symmetry == "()" do return i == 0
	if symmetry == "(x)" do return i == 0 || i == 1
	if symmetry == "(z)" do return i == 0 || i == 17
	if symmetry == "(xy)" do return i < 8
	if symmetry == "(xyz+)" do return (i % 2) == 0
	return true
}

append_cube_symmetries :: proc(g: ^Grid, rules: ^[dynamic]Rule, base: Rule, symmetry := "") {
	s: [48]Rule
	s[0] = base
	s[1] = rule_reflected(g, &s[0])
	s[2] = rule_z_rotated(g, &s[0])
	s[3] = rule_reflected(g, &s[2])
	s[4] = rule_z_rotated(g, &s[2])
	s[5] = rule_reflected(g, &s[4])
	s[6] = rule_z_rotated(g, &s[4])
	s[7] = rule_reflected(g, &s[6])
	s[8] = rule_y_rotated(g, &s[0])
	s[9] = rule_reflected(g, &s[8])
	s[10] = rule_y_rotated(g, &s[2])
	s[11] = rule_reflected(g, &s[10])
	s[12] = rule_y_rotated(g, &s[4])
	s[13] = rule_reflected(g, &s[12])
	s[14] = rule_y_rotated(g, &s[6])
	s[15] = rule_reflected(g, &s[14])
	s[16] = rule_y_rotated(g, &s[8])
	s[17] = rule_reflected(g, &s[16])
	s[18] = rule_y_rotated(g, &s[10])
	s[19] = rule_reflected(g, &s[18])
	s[20] = rule_y_rotated(g, &s[12])
	s[21] = rule_reflected(g, &s[20])
	s[22] = rule_y_rotated(g, &s[14])
	s[23] = rule_reflected(g, &s[22])
	s[24] = rule_y_rotated(g, &s[16])
	s[25] = rule_reflected(g, &s[24])
	s[26] = rule_y_rotated(g, &s[18])
	s[27] = rule_reflected(g, &s[26])
	s[28] = rule_y_rotated(g, &s[20])
	s[29] = rule_reflected(g, &s[28])
	s[30] = rule_y_rotated(g, &s[22])
	s[31] = rule_reflected(g, &s[30])
	s[32] = rule_z_rotated(g, &s[8])
	s[33] = rule_reflected(g, &s[32])
	s[34] = rule_z_rotated(g, &s[10])
	s[35] = rule_reflected(g, &s[34])
	s[36] = rule_z_rotated(g, &s[12])
	s[37] = rule_reflected(g, &s[36])
	s[38] = rule_z_rotated(g, &s[14])
	s[39] = rule_reflected(g, &s[38])
	s[40] = rule_z_rotated(g, &s[24])
	s[41] = rule_reflected(g, &s[40])
	s[42] = rule_z_rotated(g, &s[26])
	s[43] = rule_reflected(g, &s[42])
	s[44] = rule_z_rotated(g, &s[28])
	s[45] = rule_reflected(g, &s[44])
	s[46] = rule_z_rotated(g, &s[30])
	s[47] = rule_reflected(g, &s[46])

	used: [48]bool
	for i in 0..<48 {
		if !cube_symmetry_enabled(symmetry, i) {
			rule_destroy(&s[i])
			continue
		}
		duplicate := false
		for j in 0..<i {
			if used[j] && rule_same(&s[j], &s[i]) {
				duplicate = true
				break
			}
		}
		if duplicate {
			rule_destroy(&s[i])
		} else {
			used[i] = true
			append(rules, s[i])
		}
	}
}
