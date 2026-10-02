package markov_junior

run_parallel_node :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, steps: int) -> bool {
	current_changes := make([dynamic]Cell)
	defer delete(current_changes)
	newstate := make([]u8, len(g.state))
	defer delete(newstate)

	counter := 0
	changed := false
	for steps <= 0 || counter < steps {
		clear(&current_changes)
		// C# ParallelNode never sets lastMatchedTurn, so RuleNode.Go performs a full scan every turn.
		parallel_initial_scan(g, rules, random, newstate, &current_changes)

		if len(current_changes) == 0 {
			break
		}

		for c in current_changes {
			i := c.x + c.y * g.mx + c.z * g.mx * g.my
			g.state[i] = newstate[i]
		}

		counter += 1
		changed = true
	}
	return changed
}

parallel_initial_scan :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, newstate: []u8, changes: ^[dynamic]Cell) {
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
						parallel_try_add(g, rules, r, sx, sy, sz, random, newstate, changes)
					}
				}
			}
		}
	}
}

parallel_scan_around_changes :: proc(g: ^Grid, rules: []Rule, previous_changes: []Cell, random: ^MJRandom, newstate: []u8, changes: ^[dynamic]Cell) {
	for c in previous_changes {
		value := g.state[c.x + c.y * g.mx + c.z * g.mx * g.my]
		for r in 0..<len(rules) {
			rule := &rules[r]
			for shift in rule.ishifts[value] {
				sx := c.x - shift.x
				sy := c.y - shift.y
				sz := c.z - shift.z
				parallel_try_add(g, rules, r, sx, sy, sz, random, newstate, changes)
			}
		}
	}
}

parallel_try_add :: proc(g: ^Grid, rules: []Rule, r, sx, sy, sz: int, random: ^MJRandom, newstate: []u8, changes: ^[dynamic]Cell) {
	rule := &rules[r]
	if sx < 0 || sy < 0 || sz < 0 || sx + rule.imx > g.mx || sy + rule.imy > g.my || sz + rule.imz > g.mz {
		return
	}
	if !grid_matches(g, rule, sx, sy, sz) {
		return
	}
	if mj_random_next_f64(random) > rule.p {
		return
	}

	for dz in 0..<rule.omz {
		for dy in 0..<rule.omy {
			for dx in 0..<rule.omx {
				new_value := rule.output[dx + dy * rule.omx + dz * rule.omx * rule.omy]
				idi := sx + dx + (sy + dy) * g.mx + (sz + dz) * g.mx * g.my
				if new_value != 0xff && new_value != g.state[idi] {
					newstate[idi] = new_value
					append(changes, Cell{sx + dx, sy + dy, sz + dz})
				}
			}
		}
	}
}
