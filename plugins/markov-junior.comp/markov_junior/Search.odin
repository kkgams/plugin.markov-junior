package markov_junior

import "core:math"

Search_Board :: struct {
	state: []u8,
	parent, depth, backward, forward: int,
	priority: f64,
}

search_destroy_trajectory :: proc(t: [][]u8) {
	for i in 0..<len(t) do if t[i] != nil do delete(t[i])
	if t != nil do delete(t)
}

search_run :: proc(present: []u8, future: []i32, rules: []Rule, mx, my, mz, c_count: int, all: bool, limit: int, depth_coef: f64, seed: i32) -> [][]u8 {
	if all || mz != 1 do return nil
	bpot := make([]int, c_count * len(present)); defer delete(bpot)
	fpot := make([]int, c_count * len(present)); defer delete(fpot)
	observations_compute_backward_potentials(bpot, future, mx, my, mz, c_count, rules)
	root_b := observations_backward_pointwise(bpot, present, c_count)
	observations_compute_forward_potentials(fpot, present, mx, my, mz, c_count, rules)
	root_f := observations_forward_pointwise(fpot, future, c_count)
	if root_b < 0 || root_f < 0 do return nil
	if root_b == 0 do return make([][]u8, 0)

	random := mj_random_init(seed)
	boards := make([dynamic]Search_Board)
	defer {
		for i in 0..<len(boards) do if boards[i].state != nil do delete(boards[i].state)
		delete(boards)
	}
	root_state := make([]u8, len(present)); copy(root_state, present)
	append(&boards, Search_Board{root_state, -1, 0, root_b, root_f, search_rank(0, root_b, root_f, depth_coef, &random)})
	frontier := make([dynamic]int); defer delete(frontier)
	append(&frontier, 0)

	for len(frontier) > 0 && (limit < 0 || len(boards) < limit) {
		fi := search_frontier_pop_min(&frontier, boards[:])
		parent := boards[fi]
		children := search_one_child_states(parent.state, mx, my, rules)
		for child in children {
			if search_find_state(boards[:], child) >= 0 { delete(child); continue }
			child_b := observations_backward_pointwise(bpot, child, c_count)
			observations_compute_forward_potentials(fpot, child, mx, my, mz, c_count, rules)
			child_f := observations_forward_pointwise(fpot, future, c_count)
			if child_b < 0 || child_f < 0 { delete(child); continue }
			idx := len(boards)
			append(&boards, Search_Board{child, fi, parent.depth + 1, child_b, child_f, search_rank(parent.depth + 1, child_b, child_f, depth_coef, &random)})
			if child_f == 0 {
				return search_trajectory(idx, boards[:])
			}
			append(&frontier, idx)
		}
		delete(children)
	}
	return nil
}

search_rank :: proc(depth, backward, forward: int, depth_coef: f64, random: ^MJRandom) -> f64 {
	result := f64(forward + backward) + 2.0 * depth_coef * f64(depth)
	if depth_coef < 0 do result = 1000.0 - f64(depth)
	return result + 0.0001 * mj_random_next_f64(random)
}

search_frontier_pop_min :: proc(frontier: ^[dynamic]int, boards: []Search_Board) -> int {
	best := 0
	bestp := boards[frontier[0]].priority
	for i in 1..<len(frontier) {
		p := boards[frontier[i]].priority
		if p < bestp { bestp = p; best = i }
	}
	idx := frontier[best]
	ordered_remove(frontier, best)
	return idx
}

search_find_state :: proc(boards: []Search_Board, state: []u8) -> int {
	for i in 0..<len(boards) {
		if len(boards[i].state) != len(state) do continue
		same := true
		for j in 0..<len(state) do if boards[i].state[j] != state[j] { same = false; break }
		if same do return i
	}
	return -1
}

search_one_child_states :: proc(state: []u8, mx, my: int, rules: []Rule) -> [dynamic][]u8 {
	result := make([dynamic][]u8)
	for r in 0..<len(rules) {
		rule := &rules[r]
		for y in 0..<my do for x in 0..<mx do if search_matches(rule, x, y, state, mx, my) {
			append(&result, search_applied(rule, x, y, state, mx))
		}
	}
	return result
}

search_matches :: proc(rule: ^Rule, x, y: int, state: []u8, mx, my: int) -> bool {
	if x + rule.imx > mx || y + rule.imy > my do return false
	dx, dy := 0, 0
	for di in 0..<len(rule.input) {
		if (rule.input[di] & (i32(1) << uint(state[x + dx + (y + dy) * mx]))) == 0 do return false
		dx += 1
		if dx == rule.imx { dx = 0; dy += 1 }
	}
	return true
}

search_applied :: proc(rule: ^Rule, x, y: int, state: []u8, mx: int) -> []u8 {
	res := make([]u8, len(state)); copy(res, state)
	for dz in 0..<rule.omz do for dy in 0..<rule.omy do for dx in 0..<rule.omx {
		newv := rule.output[dx + dy * rule.omx + dz * rule.omx * rule.omy]
		if newv != 0xff do res[x + dx + (y + dy) * mx] = newv
	}
	return res
}

search_trajectory :: proc(index: int, boards: []Search_Board) -> [][]u8 {
	count := 0
	for i := index; i >= 0; i = boards[i].parent { count += 1; if boards[i].parent < 0 do break }
	// exclude root, then reverse parent chain to root->goal order.
	traj := make([][]u8, count - 1)
	out := count - 2
	for i := index; boards[i].parent >= 0; i = boards[i].parent {
		state := make([]u8, len(boards[i].state)); copy(state, boards[i].state)
		traj[out] = state
		out -= 1
	}
	return traj
}

observations_compute_forward_potentials :: proc(potentials: []int, state: []u8, mx, my, mz, c_count: int, rules: []Rule) {
	state_len := len(state)
	for c in 0..<c_count do for i in 0..<state_len do potentials[c * state_len + i] = -1
	for i in 0..<state_len do potentials[int(state[i]) * state_len + i] = 0
	observations_compute_potentials(potentials, mx, my, mz, c_count, rules, false)
}

observations_forward_pointwise :: proc(potentials: []int, future: []i32, c_count: int) -> int {
	state_len := len(future)
	sum := 0
	for i in 0..<state_len {
		f := future[i]
		min := 1000
		arg := -1
		for c in 0..<c_count {
			p := potentials[c * state_len + i]
			if (f & (i32(1) << uint(c))) != 0 && p >= 0 && p < min { min = p; arg = c }
		}
		if arg < 0 do return -1
		sum += min
	}
	return sum
}

observations_backward_pointwise :: proc(potentials: []int, present: []u8, c_count: int) -> int {
	state_len := len(present)
	sum := 0
	for i in 0..<state_len {
		p := potentials[int(present[i]) * state_len + i]
		if p < 0 do return -1
		sum += p
	}
	return sum
}
