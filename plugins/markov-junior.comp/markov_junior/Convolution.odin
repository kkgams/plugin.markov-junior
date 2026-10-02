package markov_junior

import xml "core:encoding/xml"
import "core:strings"
import "core:strconv"

Convolution_Rule :: struct {
	input, output: u8,
	values: [dynamic]u8,
	sums: []bool,
	p: f64,
}

Convolution_State :: struct {
	rules: [dynamic]Convolution_Rule,
	kernel: []int,
	periodic: bool,
	counter, steps: int,
	sumfield: []int,
	c: int,
}

convolution_destroy :: proc(c: ^Convolution_State) {
	for i in 0..<len(c.rules) {
		if c.rules[i].values != nil do delete(c.rules[i].values)
		if c.rules[i].sums != nil do delete(c.rules[i].sums)
	}
	if c.rules != nil do delete(c.rules)
	if c.kernel != nil do delete(c.kernel)
	if c.sumfield != nil do delete(c.sumfield)
}

convolution_load :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid) -> Convolution_State {
	c := Convolution_State{}
	c.steps = xml_attr_int(doc, id, "steps", -1)
	c.periodic = xml_attr_bool(doc, id, "periodic")
	c.c = len(g.characters)
	neighborhood := xml_attr(doc, id, "neighborhood")
	c.kernel = convolution_kernel(g.mz == 1, neighborhood)
	c.sumfield = make([]int, len(g.state) * c.c)

	loaded_child := false
	for value in doc.elements[id].value {
		#partial switch child_id in value {
		case xml.Element_ID:
			if doc.elements[child_id].ident == "rule" {
				append(&c.rules, convolution_rule_load(doc, child_id, g))
				loaded_child = true
			}
		}
	}
	if !loaded_child {
		append(&c.rules, convolution_rule_load(doc, id, g))
	}
	return c
}

convolution_kernel :: proc(d2: bool, name: string) -> []int {
	if d2 {
		k := make([]int, 9)
		if name == "VonNeumann" {
			copy(k, []int{0,1,0, 1,0,1, 0,1,0})
		} else {
			copy(k, []int{1,1,1, 1,0,1, 1,1,1})
		}
		return k
	}
	k := make([]int, 27)
	if name == "VonNeumann" {
		copy(k, []int{0,0,0, 0,1,0, 0,0,0, 0,1,0, 1,0,1, 0,1,0, 0,0,0, 0,1,0, 0,0,0})
	} else {
		copy(k, []int{0,1,0, 1,1,1, 0,1,0, 1,1,1, 1,0,1, 1,1,1, 0,1,0, 1,1,1, 0,1,0})
	}
	return k
}

convolution_rule_load :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid) -> Convolution_Rule {
	r := Convolution_Rule{}
	r.input = grid_value(g, xml_attr(doc, id, "in")[0])
	r.output = grid_value(g, xml_attr(doc, id, "out")[0])
	r.p = xml_attr_f64(doc, id, "p", 1.0)
	values := xml_attr(doc, id, "values", "")
	sums := xml_attr(doc, id, "sum", "")
	if values != "" {
		for i in 0..<len(values) do append(&r.values, grid_value(g, values[i]))
		r.sums = make([]bool, 28)
		parts := strings.split(sums, ",")
		defer delete(parts)
		for part in parts {
			if strings.contains(part, "..") {
				bounds := strings.split(part, "..")
				lo, _ := strconv.parse_int(bounds[0])
				hi, _ := strconv.parse_int(bounds[1])
				delete(bounds)
				for v := int(lo); v <= int(hi); v += 1 do r.sums[v] = true
			} else {
				v, _ := strconv.parse_int(part)
				r.sums[int(v)] = true
			}
		}
	}
	return r
}

convolution_go :: proc(c: ^Convolution_State, g: ^Grid, random: ^MJRandom) -> bool {
	if c.steps > 0 && c.counter >= c.steps do return false
	for i in 0..<len(c.sumfield) do c.sumfield[i] = 0
	if g.mz == 1 {
		for y in 0..<g.my do for x in 0..<g.mx {
			base := (x + y * g.mx) * c.c
			for dy := -1; dy <= 1; dy += 1 do for dx := -1; dx <= 1; dx += 1 {
				sx := x + dx; sy := y + dy
				if c.periodic {
					if sx < 0 { sx += g.mx } else if sx >= g.mx { sx -= g.mx }
					if sy < 0 { sy += g.my } else if sy >= g.my { sy -= g.my }
				} else if sx < 0 || sy < 0 || sx >= g.mx || sy >= g.my do continue
				c.sumfield[base + int(g.state[sx + sy * g.mx])] += c.kernel[dx + 1 + (dy + 1) * 3]
			}
		}
	} else {
		for z in 0..<g.mz do for y in 0..<g.my do for x in 0..<g.mx {
			base := (x + y * g.mx + z * g.mx * g.my) * c.c
			for dz := -1; dz <= 1; dz += 1 do for dy := -1; dy <= 1; dy += 1 do for dx := -1; dx <= 1; dx += 1 {
				sx := x + dx; sy := y + dy; sz := z + dz
				if c.periodic {
					if sx < 0 { sx += g.mx } else if sx >= g.mx { sx -= g.mx }
					if sy < 0 { sy += g.my } else if sy >= g.my { sy -= g.my }
					if sz < 0 { sz += g.mz } else if sz >= g.mz { sz -= g.mz }
				} else if sx < 0 || sy < 0 || sz < 0 || sx >= g.mx || sy >= g.my || sz >= g.mz do continue
				c.sumfield[base + int(g.state[sx + sy * g.mx + sz * g.mx * g.my])] += c.kernel[dx + 1 + (dy + 1) * 3 + (dz + 1) * 9]
			}
		}
	}

	change := false
	for i in 0..<len(g.state) {
		input := g.state[i]
		base := i * c.c
		for r in c.rules {
			if input == r.input && r.output != g.state[i] && (r.p == 1.0 || f64(mj_random_next(random)) < r.p * 2147483647.0) {
				success := true
				if r.sums != nil {
					sum := 0
					for v in r.values do sum += c.sumfield[base + int(v)]
					success = r.sums[sum]
				}
				if success {
					g.state[i] = r.output
					change = true
					break
				}
			}
		}
	}
	c.counter += 1
	return change
}
