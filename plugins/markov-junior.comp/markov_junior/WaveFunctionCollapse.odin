package markov_junior

import "core:math"

WFC_Wave :: struct {
	data: []bool,
	compatible: []int,
	sums: []int,
	sums_weights: []f64,
	sums_weight_log_weights: []f64,
	entropies: []f64,
	length, p, d: int,
	shannon: bool,
}

wfc_ln :: proc(x: f64) -> f64 {
	if x <= 0 do return -1e300
	return math.ln(x)
}

wfc_wave_make :: proc(length, p, d: int, shannon: bool) -> WFC_Wave {
	w := WFC_Wave{length = length, p = p, d = d, shannon = shannon}
	w.data = make([]bool, length * p)
	w.compatible = make([]int, length * p * d)
	w.sums = make([]int, length)
	if shannon {
		w.sums_weights = make([]f64, length)
		w.sums_weight_log_weights = make([]f64, length)
		w.entropies = make([]f64, length)
	}
	return w
}

wfc_wave_destroy :: proc(w: ^WFC_Wave) {
	if w.data != nil do delete(w.data)
	if w.compatible != nil do delete(w.compatible)
	if w.sums != nil do delete(w.sums)
	if w.sums_weights != nil do delete(w.sums_weights)
	if w.sums_weight_log_weights != nil do delete(w.sums_weight_log_weights)
	if w.entropies != nil do delete(w.entropies)
}

wfc_wave_init :: proc(w: ^WFC_Wave, propagator: [][][]int, sum_weights, sum_weight_log_weights, starting_entropy: f64) {
	opposite := [?]int{2, 3, 0, 1, 5, 4}
	for i in 0..<w.length {
		for p in 0..<w.p {
			w.data[i * w.p + p] = true
			for d in 0..<w.d do w.compatible[(i * w.p + p) * w.d + d] = len(propagator[opposite[d]][p])
		}
		w.sums[i] = w.p
		if w.shannon {
			w.sums_weights[i] = sum_weights
			w.sums_weight_log_weights[i] = sum_weight_log_weights
			w.entropies[i] = starting_entropy
		}
	}
}

wfc_wave_copy :: proc(dst, src: ^WFC_Wave) {
	copy(dst.data, src.data)
	copy(dst.compatible, src.compatible)
	copy(dst.sums, src.sums)
	if dst.shannon {
		copy(dst.sums_weights, src.sums_weights)
		copy(dst.sums_weight_log_weights, src.sums_weight_log_weights)
		copy(dst.entropies, src.entropies)
	}
}

WFC_State :: struct {
	wave, startwave: WFC_Wave,
	propagator: [][][]int,
	p, n: int,
	weights, weight_log_weights, distribution: []f64,
	sum_weights, sum_weight_log_weights, starting_entropy: f64,
	newgrid: Grid,
	map_values: [dynamic]u8,
	map_positions: [dynamic][]bool,
	periodic, shannon: bool,
	tries: int,
	stack_i, stack_t: []int,
	stacksize: int,
	firstgo: bool,
	counter: int,
	random: MJRandom,
	patterns: [][]u8,
	tile_mode: bool,
	preview_updates: bool,
	tile_s, tile_sz, overlap, overlapz: int,
}

wfc_destroy :: proc(w: ^WFC_State) {
	wfc_wave_destroy(&w.wave); wfc_wave_destroy(&w.startwave)
	for d in 0..<len(w.propagator) { for p in 0..<len(w.propagator[d]) do if w.propagator[d][p] != nil do delete(w.propagator[d][p]); if w.propagator[d] != nil do delete(w.propagator[d]) }
	if w.propagator != nil do delete(w.propagator)
	if w.weights != nil do delete(w.weights)
	if w.weight_log_weights != nil do delete(w.weight_log_weights)
	if w.distribution != nil do delete(w.distribution)
	grid_destroy(&w.newgrid)
	if w.map_values != nil do delete(w.map_values)
	for i in 0..<len(w.map_positions) do if w.map_positions[i] != nil do delete(w.map_positions[i])
	if w.map_positions != nil do delete(w.map_positions)
	if w.stack_i != nil do delete(w.stack_i)
	if w.stack_t != nil do delete(w.stack_t)
	for i in 0..<len(w.patterns) do if w.patterns[i] != nil do delete(w.patterns[i])
	if w.patterns != nil do delete(w.patterns)
}

wfc_base_finish :: proc(w: ^WFC_State, g: ^Grid) {
	w.wave = wfc_wave_make(len(g.state), w.p, len(w.propagator), w.shannon)
	w.startwave = wfc_wave_make(len(g.state), w.p, len(w.propagator), w.shannon)
	w.stack_i = make([]int, len(g.state) * w.p)
	w.stack_t = make([]int, len(g.state) * w.p)
	if w.shannon {
		w.weight_log_weights = make([]f64, w.p)
		for t in 0..<w.p {
			w.weight_log_weights[t] = w.weights[t] * wfc_ln(w.weights[t])
			w.sum_weights += w.weights[t]
			w.sum_weight_log_weights += w.weight_log_weights[t]
		}
		w.starting_entropy = wfc_ln(w.sum_weights) - w.sum_weight_log_weights / w.sum_weights
	}
	w.distribution = make([]f64, w.p)
	w.firstgo = true
}

wfc_go :: proc(w: ^WFC_State, g: ^Grid, random: ^MJRandom) -> bool {
	if w.counter >= 0 do return wfc_go_children_done(w, g, random)
	if w.firstgo {
		// debug
		wfc_wave_init(&w.wave, w.propagator, w.sum_weights, w.sum_weight_log_weights, w.starting_entropy)
		for i in 0..<len(g.state) {
			if pos := wfc_map_get(w, g.state[i]); pos != nil {
				for t in 0..<w.p do if !pos[t] do wfc_ban(w, i, t)
			}
		}
		if !wfc_propagate(w, g) do return false
		wfc_wave_copy(&w.startwave, &w.wave)
		good, seed := wfc_good_seed(w, g, random)
		if !good do return false
		w.random = mj_random_init(seed)
		w.stacksize = 0
		wfc_wave_copy(&w.wave, &w.startwave)
		w.firstgo = false
		if w.tile_mode {
			for i in 0..<len(w.newgrid.state) do w.newgrid.state[i] = 0
			// Tile WFC observes on the original coarse grid, but C# switches
			// interpreter output to the expanded tile grid immediately. The component
			// keeps `g` coarse for WFC computation and returns `newgrid` as the output
			// grid while observation is still in progress.
			return true
		}
		for i in 0..<len(w.newgrid.state) do w.newgrid.state[i] = 0
		old := g^; g^ = w.newgrid; w.newgrid = old
		return true
	}
	node := wfc_next_unobserved(w, g, &w.random)
	if node >= 0 {
		wfc_observe(w, node, &w.random)
		wfc_propagate(w, g)
		if w.preview_updates {
			// Session stepping should expose WFC's incremental observation state to
			// the browser preview.  Use a copy of the host random so preview frames do
			// not consume the random value used by the final C#-parity update.
			preview_random := random^
			if w.tile_mode {
				wfc_tile_update_to(w, &w.newgrid, g.mx, g.my, g.mz, &preview_random)
			} else {
				wfc_overlap_update(w, g, &preview_random)
			}
		}
	} else {
		if w.tile_mode {
			for i in 0..<len(w.newgrid.state) do w.newgrid.state[i] = 0
			wfc_tile_update_to(w, &w.newgrid, g.mx, g.my, g.mz, random)
			w.counter = 0
			old := g^; g^ = w.newgrid; w.newgrid = old
		} else {
			w.counter += 1
		}
	}
	if w.counter >= 0 {
		if !w.tile_mode do wfc_overlap_update(w, g, random)
	}
	return true
}

wfc_go_children_done :: proc(w: ^WFC_State, g: ^Grid, random: ^MJRandom) -> bool { return false }

wfc_map_get :: proc(w: ^WFC_State, value: u8) -> []bool {
	for i in 0..<len(w.map_values) do if w.map_values[i] == value do return w.map_positions[i]
	return nil
}

wfc_good_seed :: proc(w: ^WFC_State, g: ^Grid, random: ^MJRandom) -> (bool, i32) {
	for k in 0..<w.tries {
		seed := mj_random_next(random)
		w.random = mj_random_init(seed)
		w.stacksize = 0
		wfc_wave_copy(&w.wave, &w.startwave)
		for {
			node := wfc_next_unobserved(w, g, &w.random)
			if node >= 0 {
				wfc_observe(w, node, &w.random)
				if !wfc_propagate(w, g) do break
			} else {
				return true, seed
			}
		}
	}
	return false, 0
}

wfc_next_unobserved :: proc(w: ^WFC_State, g: ^Grid, random: ^MJRandom) -> int {
	min: f64 = 1e4
	argmin := -1
	for z in 0..<g.mz do for y in 0..<g.my do for x in 0..<g.mx {
		if !w.periodic && (x + w.n > g.mx || y + w.n > g.my || z + 1 > g.mz) do continue
		i := x + y * g.mx + z * g.mx * g.my
		remaining := w.wave.sums[i]
		entropy := f64(remaining)
		if w.shannon do entropy = w.wave.entropies[i]
		if remaining > 1 && entropy <= min {
			noise := 1e-6 * mj_random_next_f64(random)
			if entropy + noise < min { min = entropy + noise; argmin = i }
		}
	}
	return argmin
}

wfc_observe :: proc(w: ^WFC_State, node: int, random: ^MJRandom) {
	for t in 0..<w.p {
		if w.wave.data[node * w.p + t] {
			w.distribution[t] = w.weights[t]
		} else {
			w.distribution[t] = 0
		}
	}
	r := weighted_random(w.distribution, mj_random_next_f64(random))
	for t in 0..<w.p do if w.wave.data[node * w.p + t] != (t == r) do wfc_ban(w, node, t)
}

weighted_random :: proc(weights: []f64, r: f64) -> int {
	sum := 0.0
	for v in weights do sum += v
	threshold := r * sum
	partial := 0.0
	for i in 0..<len(weights) { partial += weights[i]; if partial >= threshold do return i }
	return 0
}

wfc_propagate :: proc(w: ^WFC_State, g: ^Grid) -> bool {
	dx := [?]int{1,0,-1,0,0,0}; dy := [?]int{0,1,0,-1,0,0}; dz := [?]int{0,0,0,0,1,-1}
	for w.stacksize > 0 {
		w.stacksize -= 1
		i1 := w.stack_i[w.stacksize]; p1 := w.stack_t[w.stacksize]
		x1 := i1 % g.mx; y1 := (i1 % (g.mx * g.my)) / g.mx; z1 := i1 / (g.mx * g.my)
		for d in 0..<len(w.propagator) {
			x2 := x1 + dx[d]; y2 := y1 + dy[d]; z2 := z1 + dz[d]
			if !w.periodic && (x2 < 0 || y2 < 0 || z2 < 0 || x2 + w.n > g.mx || y2 + w.n > g.my || z2 + 1 > g.mz) do continue
			if x2 < 0 { x2 += g.mx } else if x2 >= g.mx { x2 -= g.mx }
			if y2 < 0 { y2 += g.my } else if y2 >= g.my { y2 -= g.my }
			if z2 < 0 { z2 += g.mz } else if z2 >= g.mz { z2 -= g.mz }
			i2 := x2 + y2 * g.mx + z2 * g.mx * g.my
			for t2 in w.propagator[d][p1] {
				ci := (i2 * w.p + t2) * len(w.propagator) + d
				w.wave.compatible[ci] -= 1
				if w.wave.compatible[ci] == 0 do wfc_ban(w, i2, t2)
			}
		}
	}
	return w.wave.sums[0] > 0
}

wfc_ban :: proc(w: ^WFC_State, i, t: int) {
	if !w.wave.data[i * w.p + t] do return
	w.wave.data[i * w.p + t] = false
	for d in 0..<len(w.propagator) do w.wave.compatible[(i * w.p + t) * len(w.propagator) + d] = 0
	w.stack_i[w.stacksize] = i; w.stack_t[w.stacksize] = t; w.stacksize += 1
	w.wave.sums[i] -= 1
	if w.shannon {
		sum := w.wave.sums_weights[i]
		w.wave.entropies[i] += w.wave.sums_weight_log_weights[i] / sum - wfc_ln(sum)
		w.wave.sums_weights[i] -= w.weights[t]
		w.wave.sums_weight_log_weights[i] -= w.weight_log_weights[t]
		sum = w.wave.sums_weights[i]
		if sum > 0 {
			w.wave.entropies[i] -= w.wave.sums_weight_log_weights[i] / sum - wfc_ln(sum)
		} else {
			w.wave.entropies[i] = 0
		}
	}
}
