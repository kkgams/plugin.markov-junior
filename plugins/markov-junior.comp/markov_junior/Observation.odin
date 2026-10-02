package markov_junior

import xml "core:encoding/xml"

Observation_State :: struct {
	present: bool,
	from: u8,
	to: i32,
}

observation_load :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid) -> (u8, Observation_State) {
	value := grid_value(g, xml_attr(doc, id, "value")[0])
	from_s := xml_attr(doc, id, "from", xml_attr(doc, id, "value"))
	return value, Observation_State{present = true, from = grid_value(g, from_s[0]), to = grid_wave_string(g, xml_attr(doc, id, "to"))}
}

observations_compute_future_set_present :: proc(future: []i32, state: []u8, observations: []Observation_State) -> bool {
	mask := make([]bool, len(observations))
	defer delete(mask)
	for k in 0..<len(observations) do if !observations[k].present do mask[k] = true
	for i in 0..<len(state) {
		value := state[i]
		obs := observations[value]
		mask[value] = true
		if obs.present {
			future[i] = obs.to
			state[i] = obs.from
		} else {
			future[i] = i32(1) << uint(value)
		}
	}
	for k in 0..<len(mask) do if !mask[k] do return false
	return true
}

observations_compute_backward_potentials :: proc(potentials: []int, future: []i32, mx, my, mz, c_count: int, rules: []Rule) {
	state_len := len(future)
	for c in 0..<c_count {
		for i in 0..<state_len {
			if (future[i] & (i32(1) << uint(c))) != 0 {
				potentials[c * state_len + i] = 0
			} else {
				potentials[c * state_len + i] = -1
			}
		}
	}
	observations_compute_potentials(potentials, mx, my, mz, c_count, rules, true)
}

observations_compute_potentials :: proc(potentials: []int, mx, my, mz, c_count: int, rules: []Rule, backwards: bool) {
	Q :: struct {c: int, x, y, z: int}
	q := make([dynamic]Q)
	defer delete(q)
	state_len := mx * my * mz
	for c in 0..<c_count do for i in 0..<state_len do if potentials[c * state_len + i] == 0 {
		append(&q, Q{c, i % mx, (i % (mx * my)) / mx, i / (mx * my)})
	}
	match_mask := make([][]bool, len(rules))
	defer {
		for r in 0..<len(match_mask) do if match_mask[r] != nil do delete(match_mask[r])
		delete(match_mask)
	}
	for r in 0..<len(rules) do match_mask[r] = make([]bool, state_len)
	head := 0
	for head < len(q) {
		item := q[head]; head += 1
		i := item.x + item.y * mx + item.z * mx * my
		t := potentials[item.c * state_len + i]
		for r in 0..<len(rules) {
			rule := &rules[r]
			shifts := rule.ishifts[item.c]
			if backwards do shifts = rule.oshifts[item.c]
			for shift in shifts {
				sx := item.x - shift.x; sy := item.y - shift.y; sz := item.z - shift.z
				if sx < 0 || sy < 0 || sz < 0 || sx + rule.imx > mx || sy + rule.imy > my || sz + rule.imz > mz do continue
				si := sx + sy * mx + sz * mx * my
				if !match_mask[r][si] && observations_forward_matches(rule, sx, sy, sz, potentials, t, mx, my, state_len, backwards) {
					match_mask[r][si] = true
					observations_apply_forward(rule, sx, sy, sz, potentials, t, mx, my, state_len, &q, backwards)
				}
			}
		}
	}
}

observations_forward_matches :: proc(rule: ^Rule, x, y, z: int, potentials: []int, t, mx, my, state_len: int, backwards: bool) -> bool {
	dx, dy, dz := 0, 0, 0
	for di in 0..<len(rule.input) {
		value := rule.binput[di]
		if backwards do value = rule.output[di]
		if value != 0xff {
			cur := potentials[int(value) * state_len + x + dx + (y + dy) * mx + (z + dz) * mx * my]
			if cur > t || cur == -1 do return false
		}
		dx += 1
		if dx == rule.imx { dx = 0; dy += 1; if dy == rule.imy { dy = 0; dz += 1 } }
	}
	return true
}

observations_apply_forward :: proc(rule: ^Rule, x, y, z: int, potentials: []int, t, mx, my, state_len: int, q: ^[dynamic]$Q, backwards: bool) {
	for dz in 0..<rule.imz do for dy in 0..<rule.imy do for dx in 0..<rule.imx {
		idi := x + dx + (y + dy) * mx + (z + dz) * mx * my
		di := dx + dy * rule.imx + dz * rule.imx * rule.imy
		o := rule.output[di]
		if backwards do o = rule.binput[di]
		if o != 0xff && potentials[int(o) * state_len + idi] == -1 {
			potentials[int(o) * state_len + idi] = t + 1
			append(q, Q{int(o), x + dx, y + dy, z + dz})
		}
	}
}

observations_goal_reached :: proc(present: []u8, future: []i32) -> bool {
	for i in 0..<len(present) do if ((i32(1) << uint(present[i])) & future[i]) == 0 do return false
	return true
}
