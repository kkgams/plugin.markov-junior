package markov_junior

run_all_node :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, steps: int) -> bool {
	matches := make([dynamic]Match)
	defer delete(matches)
	match_mask := make([][]bool, len(rules))
	defer {
		for i in 0..<len(match_mask) {
			if match_mask[i] != nil do delete(match_mask[i])
		}
		delete(match_mask)
	}
	for r in 0..<len(rules) {
		match_mask[r] = make([]bool, len(g.state))
	}

	mask := make([]bool, len(g.state))
	defer delete(mask)
	previous_changes := make([dynamic]Cell)
	defer delete(previous_changes)
	current_changes := make([dynamic]Cell)
	defer delete(current_changes)

	counter := 0
	changed := false
	first_turn := true
	for steps <= 0 || counter < steps {
		clear(&matches)
		if first_turn {
			one_initial_scan(g, rules, &matches, match_mask)
			first_turn = false
		} else {
			one_add_around_changes(g, rules, previous_changes[:], &matches, match_mask)
		}

		if len(matches) == 0 {
			break
		}

		shuffle := make([]int, len(matches))
		for i in 0..<len(shuffle) {
			j := int(mj_random_next_max(random, i32(i + 1)))
			shuffle[i] = shuffle[j]
			shuffle[j] = i
		}

		clear(&current_changes)
		for k in 0..<len(shuffle) {
			m := matches[shuffle[k]]
			si := m.x + m.y * g.mx + m.z * g.mx * g.my
			match_mask[m.r][si] = false
			all_fit(g, &rules[m.r], m.x, m.y, m.z, mask, &current_changes)
		}
		delete(shuffle)

		for c in current_changes {
			mask[c.x + c.y * g.mx + c.z * g.mx * g.my] = false
		}

		clear(&previous_changes)
		for c in current_changes {
			append(&previous_changes, c)
		}

		counter += 1
		changed = true
	}
	return changed
}

all_fit :: proc(g: ^Grid, rule: ^Rule, x, y, z: int, mask: []bool, changes: ^[dynamic]Cell) {
	for dz in 0..<rule.omz {
		for dy in 0..<rule.omy {
			for dx in 0..<rule.omx {
				value := rule.output[dx + dy * rule.omx + dz * rule.omx * rule.omy]
				if value != 0xff && mask[x + dx + (y + dy) * g.mx + (z + dz) * g.mx * g.my] {
					return
				}
			}
		}
	}

	for dz in 0..<rule.omz {
		for dy in 0..<rule.omy {
			for dx in 0..<rule.omx {
				new_value := rule.output[dx + dy * rule.omx + dz * rule.omx * rule.omy]
				if new_value != 0xff {
					sx := x + dx
					sy := y + dy
					sz := z + dz
					si := sx + sy * g.mx + sz * g.mx * g.my
					mask[si] = true
					g.state[si] = new_value
					append(changes, Cell{sx, sy, sz})
				}
			}
		}
	}
}
