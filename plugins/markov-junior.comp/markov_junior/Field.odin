package markov_junior

import xml "core:encoding/xml"
import "core:math"

Field_State :: struct {
	present: bool,
	recompute, inversed, essential: bool,
	zero, substrate: i32,
}

field_load :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid) -> Field_State {
	f := Field_State{present = true}
	f.recompute = xml_attr_bool(doc, id, "recompute")
	f.essential = xml_attr_bool(doc, id, "essential")
	f.substrate = grid_wave_string(g, xml_attr(doc, id, "on"))
	from := xml_attr(doc, id, "from", "")
	if from != "" {
		f.inversed = true
		f.zero = grid_wave_string(g, from)
	} else {
		f.zero = grid_wave_string(g, xml_attr(doc, id, "to"))
	}
	return f
}

field_compute :: proc(f: ^Field_State, potential: []int, g: ^Grid) -> bool {
	front := make([dynamic]Path_Queue_Item)
	defer delete(front)
	for i in 0..<len(g.state) {
		potential[i] = -1
		v := g.state[i]
		if (f.zero & (i32(1) << uint(v))) != 0 {
			potential[i] = 0
			x := i % g.mx
			y := (i % (g.mx * g.my)) / g.mx
			z := i / (g.mx * g.my)
			append(&front, Path_Queue_Item{0, x, y, z})
		}
	}
	if len(front) == 0 do return false
	head := 0
	for head < len(front) {
		q := front[head]
		head += 1
		field_push(f, g, potential, &front, q.t + 1, q.x - 1, q.y, q.z)
		field_push(f, g, potential, &front, q.t + 1, q.x + 1, q.y, q.z)
		field_push(f, g, potential, &front, q.t + 1, q.x, q.y - 1, q.z)
		field_push(f, g, potential, &front, q.t + 1, q.x, q.y + 1, q.z)
		field_push(f, g, potential, &front, q.t + 1, q.x, q.y, q.z - 1)
		field_push(f, g, potential, &front, q.t + 1, q.x, q.y, q.z + 1)
	}
	return true
}

field_push :: proc(f: ^Field_State, g: ^Grid, potential: []int, front: ^[dynamic]Path_Queue_Item, t, x, y, z: int) {
	if x < 0 || y < 0 || z < 0 || x >= g.mx || y >= g.my || z >= g.mz do return
	i := x + y * g.mx + z * g.mx * g.my
	v := g.state[i]
	if potential[i] == -1 && (f.substrate & (i32(1) << uint(v))) != 0 {
		potential[i] = t
		append(front, Path_Queue_Item{t, x, y, z})
	}
}

field_delta_pointwise :: proc(state: []u8, rule: ^Rule, x, y, z: int, fields: []Field_State, potentials: []int, c_count, mx, my: int) -> (int, bool) {
	sum := 0
	dx, dy, dz := 0, 0, 0
	for di in 0..<len(rule.input) {
		new_value := rule.output[di]
		if new_value != 0xff && (rule.input[di] & (i32(1) << uint(new_value))) == 0 {
			i := x + dx + (y + dy) * mx + (z + dz) * mx * my
			new_p := potentials[int(new_value) * len(state) + i]
			if new_p == -1 do return 0, false
			old_value := state[i]
			old_p := potentials[int(old_value) * len(state) + i]
			sum += new_p - old_p
			if len(fields) > 0 {
				old_f := fields[old_value]
				if old_f.present && old_f.inversed do sum += 2 * old_p
				new_f := fields[new_value]
				if new_f.present && new_f.inversed do sum -= 2 * new_p
			}
		}
		dx += 1
		if dx == rule.imx {
			dx = 0; dy += 1
			if dy == rule.imy { dy = 0; dz += 1 }
		}
	}
	return sum, true
}

field_key :: proc(h: int, first_h: int, temperature: f64, random: ^MJRandom) -> f64 {
	u := mj_random_next_f64(random)
	if temperature > 0 do return math.pow(u, math.exp((f64(h - first_h)) / temperature))
	return -f64(h) + 0.001 * u
}
