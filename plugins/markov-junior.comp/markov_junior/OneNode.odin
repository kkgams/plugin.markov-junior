package markov_junior

Match :: struct {
	r, x, y, z: int,
}

Cell :: struct {
	x, y, z: int,
}

run_one_node :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, steps: int) -> bool {
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

	one_initial_scan(g, rules, &matches, match_mask)
	changes := make([dynamic]Cell)
	defer delete(changes)

	counter := 0
	changed := false
	for (steps <= 0 || counter < steps) && len(matches) > 0 {
		for len(matches) > 0 {
			match_index := int(mj_random_next_max(random, i32(len(matches))))
			m := matches[match_index]
			i := m.x + m.y * g.mx + m.z * g.mx * g.my
			match_mask[m.r][i] = false
			matches[match_index] = matches[len(matches) - 1]
			_ = pop(&matches)

			if grid_matches(g, &rules[m.r], m.x, m.y, m.z) {
				clear(&changes)
				one_apply(g, &rules[m.r], m.x, m.y, m.z, &changes)
				one_add_around_changes(g, rules, changes[:], &matches, match_mask)
				counter += 1
				changed = true
				break
			}
		}
	}
	return changed
}

one_initial_scan :: proc(g: ^Grid, rules: []Rule, matches: ^[dynamic]Match, match_mask: [][]bool) {
	clear(matches)
	for r in 0..<len(match_mask) {
		for i in 0..<len(match_mask[r]) {
			match_mask[r][i] = false
		}
	}

	for r in 0..<len(rules) {
		rule := &rules[r]
		for z := rule.imz - 1; z < g.mz; z += rule.imz {
			for y := rule.imy - 1; y < g.my; y += rule.imy {
				for x := rule.imx - 1; x < g.mx; x += rule.imx {
					value := g.state[x + y * g.mx + z * g.mx * g.my]
					for shift in rule.ishifts[value] {
						sx := x - shift.x
						sy := y - shift.y
						sz := z - shift.z
						one_try_add(g, rules, r, sx, sy, sz, matches, match_mask)
					}
				}
			}
		}
	}
}

one_add_around_changes :: proc(g: ^Grid, rules: []Rule, changes: []Cell, matches: ^[dynamic]Match, match_mask: [][]bool) {
	for c in changes {
		value := g.state[c.x + c.y * g.mx + c.z * g.mx * g.my]
		for r in 0..<len(rules) {
			rule := &rules[r]
			for shift in rule.ishifts[value] {
				sx := c.x - shift.x
				sy := c.y - shift.y
				sz := c.z - shift.z
				one_try_add(g, rules, r, sx, sy, sz, matches, match_mask)
			}
		}
	}
}

one_try_add :: proc(g: ^Grid, rules: []Rule, r, sx, sy, sz: int, matches: ^[dynamic]Match, match_mask: [][]bool) {
	rule := &rules[r]
	if sx < 0 || sy < 0 || sz < 0 || sx + rule.imx > g.mx || sy + rule.imy > g.my || sz + rule.imz > g.mz {
		return
	}
	si := sx + sy * g.mx + sz * g.mx * g.my
	if !match_mask[r][si] && grid_matches(g, rule, sx, sy, sz) {
		match_mask[r][si] = true
		append(matches, Match{r, sx, sy, sz})
	}
}

one_apply :: proc(g: ^Grid, rule: ^Rule, x, y, z: int, changes: ^[dynamic]Cell) {
	for dz in 0..<rule.omz {
		for dy in 0..<rule.omy {
			for dx in 0..<rule.omx {
				new_value := rule.output[dx + dy * rule.omx + dz * rule.omx * rule.omy]
				if new_value != 0xff {
					sx := x + dx
					sy := y + dy
					sz := z + dz
					si := sx + sy * g.mx + sz * g.mx * g.my
					if g.state[si] != new_value {
						g.state[si] = new_value
						append(changes, Cell{sx, sy, sz})
					}
				}
			}
		}
	}
}
