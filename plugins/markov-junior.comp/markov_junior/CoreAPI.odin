package markov_junior

import mem "core:mem"
import runtime "base:runtime"

MJ_OUTPUT_CAPACITY :: 8 * 1024 * 1024
mj_output_buffer: [MJ_OUTPUT_CAPACITY]u8
mj_output_len: int

MJ_Node :: struct {
	kind: u32,
	start: int,
	count: int,
	steps: int,
	children_start: int,
	children_count: int,
	fields: []Field_State,
	observations: []Observation_State,
	potentials: []int,
	future: []i32,
	future_computed: bool,
	trajectory: [][]u8,
	search: bool,
	limit: int,
	depth_coefficient: f64,
	path: Path_State,
	has_path: bool,
	convolution: Convolution_State,
	has_convolution: bool,
	convchain: ConvChain_State,
	has_convchain: bool,
	wfc: WFC_State,
	has_wfc: bool,
	map_state: Map_State,
	has_map: bool,
	temperature: f64,
}

MJ_Markov_State :: struct {
	matches: [dynamic]Match,
	match_mask: [][]bool,
	last_turn: int,
}

MJ_Runtime_Session :: struct {
	g: Grid,
	rules: [dynamic]Rule,
	nodes: [dynamic]MJ_Node,
	container_kind: u32,
	random: MJRandom,
	states: []MJ_Markov_State,
	counters: []int,
	positions: []int,
	active: []int,
	changes: [dynamic]Cell,
	first: [dynamic]int,
	child: int,
	steps_run: u32,
	done: bool,
}


mj_parse_sum_number :: proc(text: string, pos: ^int) -> int {
	value := 0
	for pos^ < len(text) && text[pos^] >= '0' && text[pos^] <= '9' {
		value = value * 10 + int(text[pos^] - '0')
		pos^ += 1
	}
	return value
}

mj_convolution_sums_from_string :: proc(text: string) -> []bool {
	if text == "" do return nil
	sums := make([]bool, 28)
	pos := 0
	for pos < len(text) {
		lo := mj_parse_sum_number(text, &pos)
		hi := lo
		if pos + 1 < len(text) && text[pos] == '.' && text[pos + 1] == '.' {
			pos += 2
			hi = mj_parse_sum_number(text, &pos)
		}
		for v := lo; v <= hi && v < len(sums); v += 1 do sums[v] = true
		if pos < len(text) && text[pos] == ',' do pos += 1
	}
	return sums
}

@(export)
mj_core_run :: proc "c" (
	model_ptr: rawptr,
	model_len: uintptr,
	initial_ptr: rawptr,
	initial_len: uintptr,
	width: u32,
	height: u32,
	depth: u32,
	seed: u64,
	max_steps: u32,
) -> u32 {
	context = runtime.default_context()
	model := mj_core_input_slice(model_ptr, model_len)
	initial := mj_core_input_slice(initial_ptr, initial_len)
	return mj_run_mjir_v1(model, initial, width, height, depth, seed, max_steps)
}

@(export)
mj_core_session_create :: proc "c" (
	model_ptr: rawptr,
	model_len: uintptr,
	initial_ptr: rawptr,
	initial_len: uintptr,
	width: u32,
	height: u32,
	depth: u32,
	seed: u64,
) -> rawptr {
	context = runtime.default_context()
	model := mj_core_input_slice(model_ptr, model_len)
	initial := mj_core_input_slice(initial_ptr, initial_len)
	return mj_session_create_mjir_v1(model, initial, width, height, depth, seed)
}

@(export)
mj_core_session_step :: proc "c" (session: rawptr, steps: u32) -> u32 {
	context = runtime.default_context()
	if session == nil do return mj_fail("markov session is null")
	s := cast(^MJ_Runtime_Session)session
	_, changed, done := mj_session_step_runtime(s, steps)
	output_grid := mj_output_grid_for_csharp_timing(&s.g, s.nodes[:])
	return mj_respond_grid(output_grid, s.steps_run, changed, done)
}

@(export)
mj_core_session_destroy :: proc "c" (session: rawptr) {
	context = runtime.default_context()
	if session == nil do return
	mj_session_destroy_runtime(cast(^MJ_Runtime_Session)session)
}

@(export)
mj_core_output_ptr :: proc "c" () -> rawptr {
	if mj_output_len == 0 {
		return nil
	}
	return rawptr(&mj_output_buffer[0])
}

@(export)
mj_core_output_len :: proc "c" () -> uintptr {
	return uintptr(mj_output_len)
}

mj_core_input_slice :: proc(ptr: rawptr, count: uintptr) -> []u8 {
	if count == 0 {
		return []u8{}
	}
	return mem.slice_ptr(cast(^u8)ptr, int(count))
}

mj_fail :: proc(message: string) -> u32 {
	mj_output_len = 0
	if len(message) > len(mj_output_buffer) {
		return 1
	}
	copy(mj_output_buffer[:], transmute([]u8)message)
	mj_output_len = len(message)
	return 1
}

mj_write_u32 :: proc(pos: ^int, value: u32) -> bool {
	if pos^ + 4 > len(mj_output_buffer) { return false }
	mj_output_buffer[pos^ + 0] = u8(value & 0xff)
	mj_output_buffer[pos^ + 1] = u8((value >> 8) & 0xff)
	mj_output_buffer[pos^ + 2] = u8((value >> 16) & 0xff)
	mj_output_buffer[pos^ + 3] = u8((value >> 24) & 0xff)
	pos^ += 4
	return true
}

mj_read_u32 :: proc(data: []u8, pos: ^int, ok: ^bool) -> u32 {
	if !ok^ || pos^ + 4 > len(data) {
		ok^ = false
		return 0
	}
	value := u32(data[pos^]) | (u32(data[pos^ + 1]) << 8) | (u32(data[pos^ + 2]) << 16) | (u32(data[pos^ + 3]) << 24)
	pos^ += 4
	return value
}

mj_read_f64 :: proc(data: []u8, pos: ^int, ok: ^bool) -> f64 {
	if !ok^ || pos^ + 8 > len(data) {
		ok^ = false
		return 0
	}
	bits := u64(data[pos^]) | (u64(data[pos^ + 1]) << 8) | (u64(data[pos^ + 2]) << 16) | (u64(data[pos^ + 3]) << 24) |
		(u64(data[pos^ + 4]) << 32) | (u64(data[pos^ + 5]) << 40) | (u64(data[pos^ + 6]) << 48) | (u64(data[pos^ + 7]) << 56)
	pos^ += 8
	return transmute(f64)bits
}

mj_run_mjir_v1 :: proc(model: []u8, initial: []u8, width, height, depth: u32, seed: u64, max_steps: u32) -> u32 {
	if len(model) < 20 { return mj_fail("model-ir is too short") }
	if model[0] != 'M' || model[1] != 'J' || model[2] != 'I' || model[3] != 'R' { return mj_fail("model-ir magic mismatch") }
	pos := 4
	ok := true
	version := mj_read_u32(model, &pos, &ok)
	if !ok || version != 1 { return mj_fail("unsupported model-ir version") }
	values_len := int(mj_read_u32(model, &pos, &ok))
	if !ok || values_len <= 0 || pos + values_len > len(model) { return mj_fail("invalid model-ir values") }
	values_start := pos
	values := string(model[values_start:values_start + values_len])
	pos += values_len
	rule_count := int(mj_read_u32(model, &pos, &ok))
	if !ok || rule_count <= 0 { return mj_fail("invalid model-ir rule count") }

	cell_count_u64 := u64(width) * u64(height) * u64(depth)
	if cell_count_u64 > u64(len(initial)) { return mj_fail("initial-cells shorter than configured grid") }
	cell_count := int(cell_count_u64)
	if cell_count > MJ_OUTPUT_CAPACITY { return mj_fail("grid too large for MVP output buffer") }

	g := grid_init(int(width), int(height), int(depth), values, false)
	defer grid_destroy(&g)
	copy(g.state, initial[:cell_count])

	rules := make([dynamic]Rule)
	defer {
		for i in 0..<len(rules) { rule_destroy(&rules[i]) }
		delete(rules)
	}

	nodes := make([dynamic]MJ_Node)
	defer {
		for i in 0..<len(nodes) {
			if nodes[i].fields != nil do delete(nodes[i].fields)
			if nodes[i].observations != nil do delete(nodes[i].observations)
			if nodes[i].potentials != nil do delete(nodes[i].potentials)
			if nodes[i].future != nil do delete(nodes[i].future)
			if nodes[i].trajectory != nil do search_destroy_trajectory(nodes[i].trajectory)
			if nodes[i].has_convolution do convolution_destroy(&nodes[i].convolution)
			if nodes[i].has_convchain do convchain_destroy(&nodes[i].convchain)
			if nodes[i].has_wfc do wfc_destroy(&nodes[i].wfc)
			if nodes[i].has_map do map_destroy(&nodes[i].map_state)
		}
		delete(nodes)
	}
	container_kind: u32 = 0
	node_kind: u32 = 1
	node_steps := 0
	node_start := 0
	node_open := false
	container_stack := make([dynamic]int)
	defer delete(container_stack)
	current_fields: []Field_State
	current_potentials: []int
	current_observations: []Observation_State
	current_future: []i32
	current_search := false
	current_limit := -1
	current_depth_coefficient := 0.5
	current_path: Path_State
	current_has_path := false
	current_convolution: Convolution_State
	current_has_convolution := false
	current_convchain: ConvChain_State
	current_has_convchain := false
	current_wfc: WFC_State
	current_has_wfc := false
	current_map: Map_State
	current_has_map := false
	current_temperature := 0.0
	flush_node :: proc(nodes: ^[dynamic]MJ_Node, kind: u32, start, count, steps: int, fields: ^[]Field_State, observations: ^[]Observation_State, potentials: ^[]int, future: ^[]i32, search: ^bool, limit: ^int, depth_coefficient: ^f64, path: ^Path_State, has_path: ^bool, convolution: ^Convolution_State, has_convolution: ^bool, convchain: ^ConvChain_State, has_convchain: ^bool, wfc: ^WFC_State, has_wfc: ^bool, map_state: ^Map_State, has_map: ^bool, temperature: ^f64) {
		append(nodes, MJ_Node{kind = kind, start = start, count = count, steps = steps, fields = fields^, observations = observations^, potentials = potentials^, future = future^, search = search^, limit = limit^, depth_coefficient = depth_coefficient^, path = path^, has_path = has_path^, convolution = convolution^, has_convolution = has_convolution^, convchain = convchain^, has_convchain = has_convchain^, wfc = wfc^, has_wfc = has_wfc^, map_state = map_state^, has_map = has_map^, temperature = temperature^})
		fields^ = nil
		observations^ = nil
		potentials^ = nil
		future^ = nil
		search^ = false
		limit^ = -1
		depth_coefficient^ = 0.5
		path^ = {}
		has_path^ = false
		convolution^ = {}
		has_convolution^ = false
		convchain^ = {}
		has_convchain^ = false
		wfc^ = {}
		has_wfc^ = false
		map_state^ = {}
		has_map^ = false
		temperature^ = 0
	}
	root_marker_seen := false
	for _ in 0..<rule_count {
		op := mj_read_u32(model, &pos, &ok)
		if !ok { return mj_fail("truncated model-ir rule opcode") }
		if op == 100 {
			kind := mj_read_u32(model, &pos, &ok)
			marker_steps := int(mj_read_u32(model, &pos, &ok))
			if !ok || kind < 1 || kind > 10 { return mj_fail("invalid model-ir node kind") }
			is_container_kind := kind == 4 || kind == 5 || kind == 9 || kind == 10
			if (kind == 4 || kind == 5) && !root_marker_seen && len(nodes) == 0 && !node_open {
				container_kind = kind
				root_marker_seen = true
			} else if is_container_kind {
				if node_open || len(rules) > node_start || current_fields != nil || current_observations != nil || current_search || current_has_path || current_has_convolution || current_has_convchain || current_has_wfc || current_has_map {
					flush_node(&nodes, node_kind, node_start, len(rules) - node_start, node_steps, &current_fields, &current_observations, &current_potentials, &current_future, &current_search, &current_limit, &current_depth_coefficient, &current_path, &current_has_path, &current_convolution, &current_has_convolution, &current_convchain, &current_has_convchain, &current_wfc, &current_has_wfc, &current_map, &current_has_map, &current_temperature)
					node_open = false
				}
				node_start = len(rules)
				node_steps = 0
				container_index := len(nodes)
				append(&nodes, MJ_Node{kind = kind, steps = marker_steps, children_start = container_index + 1})
				append(&container_stack, container_index)
			} else {
				if node_open || len(rules) > node_start || current_fields != nil || current_observations != nil || current_search || current_has_path || current_has_convolution || current_has_convchain || current_has_wfc || current_has_map {
					flush_node(&nodes, node_kind, node_start, len(rules) - node_start, node_steps, &current_fields, &current_observations, &current_potentials, &current_future, &current_search, &current_limit, &current_depth_coefficient, &current_path, &current_has_path, &current_convolution, &current_has_convolution, &current_convchain, &current_has_convchain, &current_wfc, &current_has_wfc, &current_map, &current_has_map, &current_temperature)
				}
				node_kind = kind
				node_steps = marker_steps
				node_start = len(rules)
				node_open = true
				root_marker_seen = true
			}
		} else if op == 101 {
			if pos >= len(model) { return mj_fail("truncated model-ir union symbol") }
			symbol := model[pos]; pos += 1
			union_values_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || union_values_len <= 0 || pos + union_values_len > len(model) { return mj_fail("invalid model-ir union values") }
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			grid_add_union(target_grid, symbol, string(model[pos:pos + union_values_len]))
			pos += union_values_len
		} else if op == 102 {
			if node_open || len(rules) > node_start || current_fields != nil || current_observations != nil || current_search || current_has_path || current_has_convolution || current_has_convchain || current_has_wfc || current_has_map {
				flush_node(&nodes, node_kind, node_start, len(rules) - node_start, node_steps, &current_fields, &current_observations, &current_potentials, &current_future, &current_search, &current_limit, &current_depth_coefficient, &current_path, &current_has_path, &current_convolution, &current_has_convolution, &current_convchain, &current_has_convchain, &current_wfc, &current_has_wfc, &current_map, &current_has_map, &current_temperature)
				node_open = false
			}
			if len(container_stack) == 0 { return mj_fail("model-ir container end without start") }
			container_index := container_stack[len(container_stack) - 1]
			_ = pop(&container_stack)
			nodes[container_index].children_count = len(nodes) - nodes[container_index].children_start
			node_start = len(rules)
			node_steps = 0
		} else if op == 103 {
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			if pos >= len(model) { return mj_fail("truncated model-ir field symbol") }
			for_symbol := model[pos]; pos += 1
			recompute := mj_read_u32(model, &pos, &ok) != 0
			essential := mj_read_u32(model, &pos, &ok) != 0
			to_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || to_len < 0 || pos + to_len > len(model) { return mj_fail("invalid model-ir field to") }
			to_string := string(model[pos:pos + to_len]); pos += to_len
			from_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || from_len < 0 || pos + from_len > len(model) { return mj_fail("invalid model-ir field from") }
			from_string := string(model[pos:pos + from_len]); pos += from_len
			on_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || on_len <= 0 || pos + on_len > len(model) { return mj_fail("invalid model-ir field on") }
			on_string := string(model[pos:pos + on_len]); pos += on_len
			if current_fields == nil {
				current_fields = make([]Field_State, len(target_grid.characters))
				current_potentials = make([]int, len(target_grid.state) * len(target_grid.characters))
			}
			field := Field_State{present = true, recompute = recompute, essential = essential, substrate = grid_wave_string(target_grid, on_string)}
			if from_len > 0 {
				field.inversed = true
				field.zero = grid_wave_string(target_grid, from_string)
			} else {
				field.zero = grid_wave_string(target_grid, to_string)
			}
			current_fields[grid_value(target_grid, for_symbol)] = field
		} else if op == 104 {
			current_temperature = mj_read_f64(model, &pos, &ok)
			if !ok { return mj_fail("invalid model-ir temperature") }
		} else if op == 105 {
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			if pos >= len(model) { return mj_fail("truncated model-ir observe value") }
			observe_value := model[pos]; pos += 1
			from_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || from_len < 0 || pos + from_len > len(model) { return mj_fail("invalid model-ir observe from") }
			from_string := string(model[pos:pos + from_len]); pos += from_len
			to_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || to_len <= 0 || pos + to_len > len(model) { return mj_fail("invalid model-ir observe to") }
			to_string := string(model[pos:pos + to_len]); pos += to_len
			if current_observations == nil {
				current_observations = make([]Observation_State, len(target_grid.characters))
				if !current_search do current_potentials = make([]int, len(target_grid.state) * len(target_grid.characters))
				current_future = make([]i32, len(target_grid.state))
			}
			from_value := observe_value
			if from_len > 0 do from_value = from_string[0]
			current_observations[grid_value(target_grid, observe_value)] = Observation_State{present = true, from = grid_value(target_grid, from_value), to = grid_wave_string(target_grid, to_string)}
		} else if op == 111 {
			current_search = mj_read_u32(model, &pos, &ok) != 0
			limit_raw := mj_read_u32(model, &pos, &ok)
			if limit_raw == 0xffffffff { current_limit = -1 } else { current_limit = int(limit_raw) }
			current_depth_coefficient = mj_read_f64(model, &pos, &ok)
			if !ok { return mj_fail("invalid model-ir search config") }
		} else if op == 107 {
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			neighborhood_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || neighborhood_len < 0 || pos + neighborhood_len > len(model) { return mj_fail("invalid model-ir convolution neighborhood") }
			neighborhood := string(model[pos:pos + neighborhood_len]); pos += neighborhood_len
			periodic := mj_read_u32(model, &pos, &ok) != 0
			rule_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || rule_len <= 0 { return mj_fail("invalid model-ir convolution rule count") }
			current_convolution = Convolution_State{kernel = convolution_kernel(target_grid.mz == 1, neighborhood), periodic = periodic, c = len(target_grid.characters), sumfield = make([]int, len(target_grid.state) * len(target_grid.characters)), steps = node_steps}
			for _r in 0..<rule_len {
				if pos + 2 > len(model) { return mj_fail("truncated model-ir convolution rule symbols") }
				input := model[pos]; output := model[pos + 1]; pos += 2
				probability := mj_read_f64(model, &pos, &ok)
				values_len := int(mj_read_u32(model, &pos, &ok))
				if !ok || values_len < 0 || pos + values_len > len(model) { return mj_fail("invalid model-ir convolution values") }
				values_string := string(model[pos:pos + values_len]); pos += values_len
				sum_len := int(mj_read_u32(model, &pos, &ok))
				if !ok || sum_len < 0 || pos + sum_len > len(model) { return mj_fail("invalid model-ir convolution sum") }
				sum_string := string(model[pos:pos + sum_len]); pos += sum_len
				rule := Convolution_Rule{input = grid_value(target_grid, input), output = grid_value(target_grid, output), p = probability, sums = mj_convolution_sums_from_string(sum_string)}
				for i in 0..<len(values_string) do append(&rule.values, grid_value(target_grid, values_string[i]))
				append(&current_convolution.rules, rule)
			}
			current_has_convolution = true
		} else if op == 108 {
			n := int(mj_read_u32(model, &pos, &ok))
			temperature := mj_read_f64(model, &pos, &ok)
			if pos + 3 > len(model) { return mj_fail("truncated model-ir convchain symbols") }
			black := model[pos]; white := model[pos + 1]; on := model[pos + 2]; pos += 3
			weights_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || n <= 0 || weights_len != (1 << uint(n * n)) { return mj_fail("invalid model-ir convchain header") }
			if pos + weights_len * 8 > len(model) { return mj_fail("truncated model-ir convchain weights") }
			weights := make([]f64, weights_len)
			for i in 0..<weights_len do weights[i] = mj_read_f64(model, &pos, &ok)
			if !ok { return mj_fail("invalid model-ir convchain weights") }
			current_convchain = ConvChain_State{n = n, steps = node_steps, temperature = temperature, c0 = grid_value(&g, black), c1 = grid_value(&g, white), substrate_color = grid_value(&g, on), substrate = make([]bool, len(g.state)), weights = weights}
			current_has_convchain = true
		} else if op == 109 {
			n := int(mj_read_u32(model, &pos, &ok))
			periodic := mj_read_u32(model, &pos, &ok) != 0
			shannon := mj_read_u32(model, &pos, &ok) != 0
			tries := int(mj_read_u32(model, &pos, &ok))
			new_values_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || n <= 0 || new_values_len <= 0 || pos + new_values_len > len(model) { return mj_fail("invalid model-ir wfc header") }
			new_values := string(model[pos:pos + new_values_len]); pos += new_values_len
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			p_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || p_count <= 0 { return mj_fail("invalid model-ir wfc pattern count") }
			pattern_len := n * n
			current_wfc = WFC_State{counter = -1, n = n, p = p_count, periodic = periodic, shannon = shannon, tries = tries, newgrid = grid_init(target_grid.mx, target_grid.my, target_grid.mz, new_values, false)}
			current_wfc.patterns = make([][]u8, p_count)
			current_wfc.weights = make([]f64, p_count)
			for pidx in 0..<p_count {
				current_wfc.weights[pidx] = mj_read_f64(model, &pos, &ok)
				if !ok || pos + pattern_len > len(model) { return mj_fail("invalid model-ir wfc pattern") }
				current_wfc.patterns[pidx] = make([]u8, pattern_len)
				copy(current_wfc.patterns[pidx], model[pos:pos + pattern_len]); pos += pattern_len
			}
			dirs := int(mj_read_u32(model, &pos, &ok))
			if !ok || dirs <= 0 { return mj_fail("invalid model-ir wfc propagator") }
			current_wfc.propagator = make([][][]int, dirs)
			for d in 0..<dirs {
				current_wfc.propagator[d] = make([][]int, p_count)
				for pidx in 0..<p_count {
					list_len := int(mj_read_u32(model, &pos, &ok))
					if !ok || list_len < 0 { return mj_fail("invalid model-ir wfc propagator list") }
					current_wfc.propagator[d][pidx] = make([]int, list_len)
					for i in 0..<list_len do current_wfc.propagator[d][pidx][i] = int(mj_read_u32(model, &pos, &ok))
				}
			}
			map_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || map_count <= 0 { return mj_fail("invalid model-ir wfc map count") }
			for _m in 0..<map_count {
				if pos >= len(model) { return mj_fail("truncated model-ir wfc map input") }
				input := model[pos]; pos += 1
				if pos + p_count > len(model) { return mj_fail("truncated model-ir wfc map positions") }
				positions := make([]bool, p_count)
				for i in 0..<p_count { positions[i] = model[pos] != 0; pos += 1 }
				append(&current_wfc.map_values, grid_value(target_grid, input))
				append(&current_wfc.map_positions, positions)
			}
			if !ok { return mj_fail("invalid model-ir wfc payload") }
			wfc_base_finish(&current_wfc, target_grid)
			if len(container_stack) > 0 && nodes[container_stack[len(container_stack) - 1]].kind == 9 {
				wfc_index := container_stack[len(container_stack) - 1]
				nodes[wfc_index].wfc = current_wfc
				nodes[wfc_index].has_wfc = true
				current_wfc = {}
			} else {
				current_has_wfc = true
			}
		} else if op == 112 {
			tile_s := int(mj_read_u32(model, &pos, &ok))
			tile_sz := int(mj_read_u32(model, &pos, &ok))
			overlap_raw := mj_read_u32(model, &pos, &ok)
			overlapz_raw := mj_read_u32(model, &pos, &ok)
			overlap := int(overlap_raw)
			overlapz := int(overlapz_raw)
			if overlap_raw > 0x7fffffff do overlap = int(i64(overlap_raw) - i64(0x100000000))
			if overlapz_raw > 0x7fffffff do overlapz = int(i64(overlapz_raw) - i64(0x100000000))
			periodic := mj_read_u32(model, &pos, &ok) != 0
			shannon := mj_read_u32(model, &pos, &ok) != 0
			tries := int(mj_read_u32(model, &pos, &ok))
			new_values_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || tile_s <= 0 || tile_sz <= 0 || new_values_len <= 0 || pos + new_values_len > len(model) { return mj_fail("invalid model-ir tile wfc header") }
			new_values := string(model[pos:pos + new_values_len]); pos += new_values_len
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			p_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || p_count <= 0 { return mj_fail("invalid model-ir tile wfc pattern count") }
			pattern_len := tile_s * tile_s * tile_sz
			mx2 := (tile_s - overlap) * target_grid.mx + overlap
			my2 := (tile_s - overlap) * target_grid.my + overlap
			mz2 := (tile_sz - overlapz) * target_grid.mz + overlapz
			current_wfc = WFC_State{counter = -1, n = 1, p = p_count, periodic = periodic, shannon = shannon, tries = tries, tile_mode = true, tile_s = tile_s, tile_sz = tile_sz, overlap = overlap, overlapz = overlapz, newgrid = grid_init(mx2, my2, mz2, new_values, false)}
			current_wfc.patterns = make([][]u8, p_count)
			current_wfc.weights = make([]f64, p_count)
			for pidx in 0..<p_count {
				current_wfc.weights[pidx] = mj_read_f64(model, &pos, &ok)
				if !ok || pos + pattern_len > len(model) { return mj_fail("invalid model-ir tile wfc pattern") }
				current_wfc.patterns[pidx] = make([]u8, pattern_len)
				copy(current_wfc.patterns[pidx], model[pos:pos + pattern_len]); pos += pattern_len
			}
			dirs := int(mj_read_u32(model, &pos, &ok))
			if !ok || dirs <= 0 { return mj_fail("invalid model-ir tile wfc propagator") }
			current_wfc.propagator = make([][][]int, dirs)
			for d in 0..<dirs {
				current_wfc.propagator[d] = make([][]int, p_count)
				for pidx in 0..<p_count {
					list_len := int(mj_read_u32(model, &pos, &ok))
					if !ok || list_len < 0 { return mj_fail("invalid model-ir tile wfc propagator list") }
					current_wfc.propagator[d][pidx] = make([]int, list_len)
					for i in 0..<list_len do current_wfc.propagator[d][pidx][i] = int(mj_read_u32(model, &pos, &ok))
				}
			}
			map_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || map_count <= 0 { return mj_fail("invalid model-ir tile wfc map count") }
			for _m in 0..<map_count {
				if pos >= len(model) { return mj_fail("truncated model-ir tile wfc map input") }
				input_char := model[pos]; pos += 1
				if pos + p_count > len(model) { return mj_fail("truncated model-ir tile wfc map positions") }
				positions := make([]bool, p_count)
				for i in 0..<p_count { positions[i] = model[pos] != 0; pos += 1 }
				input := u8(0)
				if input_char != 0 do input = grid_value(target_grid, input_char)
				append(&current_wfc.map_values, input)
				append(&current_wfc.map_positions, positions)
			}
			if !ok { return mj_fail("invalid model-ir tile wfc payload") }
			wfc_base_finish(&current_wfc, target_grid)
			if len(container_stack) > 0 && nodes[container_stack[len(container_stack) - 1]].kind == 9 {
				wfc_index := container_stack[len(container_stack) - 1]
				nodes[wfc_index].wfc = current_wfc
				nodes[wfc_index].has_wfc = true
				current_wfc = {}
			} else {
				current_has_wfc = true
			}
		} else if op == 110 {
			nx := int(mj_read_u32(model, &pos, &ok)); dx := int(mj_read_u32(model, &pos, &ok))
			ny := int(mj_read_u32(model, &pos, &ok)); dy := int(mj_read_u32(model, &pos, &ok))
			nz := int(mj_read_u32(model, &pos, &ok)); dz := int(mj_read_u32(model, &pos, &ok))
			values_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || nx <= 0 || dx <= 0 || ny <= 0 || dy <= 0 || nz <= 0 || dz <= 0 || values_len <= 0 || pos + values_len > len(model) { return mj_fail("invalid model-ir map header") }
			map_values := string(model[pos:pos + values_len]); pos += values_len
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			current_map = Map_State{nx = nx, dx = dx, ny = ny, dy = dy, nz = nz, dz = dz, grid = grid_init(target_grid.mx * nx / dx, target_grid.my * ny / dy, target_grid.mz * nz / dz, map_values, false)}
			union_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || union_count < 0 { return mj_fail("invalid model-ir map union count") }
			for _u in 0..<union_count {
				if pos >= len(model) { return mj_fail("truncated model-ir map union symbol") }
				symbol := model[pos]; pos += 1
				ulen := int(mj_read_u32(model, &pos, &ok))
				if !ok || ulen < 0 || pos + ulen > len(model) { return mj_fail("truncated model-ir map union values") }
				grid_add_union(&current_map.grid, symbol, string(model[pos:pos + ulen])); pos += ulen
			}
			rule_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || rule_count <= 0 { return mj_fail("invalid model-ir map rule count") }
			for _r in 0..<rule_count {
				imx := int(mj_read_u32(model, &pos, &ok)); imy := int(mj_read_u32(model, &pos, &ok)); imz := int(mj_read_u32(model, &pos, &ok))
				omx := int(mj_read_u32(model, &pos, &ok)); omy := int(mj_read_u32(model, &pos, &ok)); omz := int(mj_read_u32(model, &pos, &ok))
				probability := mj_read_f64(model, &pos, &ok)
				symmetry_len := int(mj_read_u32(model, &pos, &ok))
				if !ok || imx <= 0 || imy <= 0 || imz <= 0 || omx <= 0 || omy <= 0 || omz <= 0 || symmetry_len < 0 { return mj_fail("invalid model-ir map rule header") }
				if pos + symmetry_len > len(model) { return mj_fail("truncated model-ir map rule symmetry") }
				symmetry := string(model[pos:pos + symmetry_len]); pos += symmetry_len
				input_len := imx * imy * imz
				output_len := omx * omy * omz
				if pos + input_len + output_len > len(model) { return mj_fail("truncated model-ir map rule data") }
				input_chars := model[pos:pos + input_len]; pos += input_len
				output_chars := model[pos:pos + output_len]; pos += output_len
				base := rule_from_char_arrays_grids(target_grid, &current_map.grid, input_chars, imx, imy, imz, output_chars, omx, omy, omz, probability)
				append_rule_symmetries(&current_map.grid, &current_map.rules, base, symmetry)
			}
			if len(container_stack) > 0 && nodes[container_stack[len(container_stack) - 1]].kind == 10 {
				map_index := container_stack[len(container_stack) - 1]
				nodes[map_index].map_state = current_map
				nodes[map_index].has_map = true
				current_map = {}
			} else {
				current_has_map = true
			}
		} else if op == 106 {
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			from_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || from_len <= 0 || pos + from_len > len(model) { return mj_fail("invalid model-ir path from") }
			from_string := string(model[pos:pos + from_len]); pos += from_len
			to_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || to_len <= 0 || pos + to_len > len(model) { return mj_fail("invalid model-ir path to") }
			to_string := string(model[pos:pos + to_len]); pos += to_len
			on_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || on_len <= 0 || pos + on_len > len(model) { return mj_fail("invalid model-ir path on") }
			on_string := string(model[pos:pos + on_len]); pos += on_len
			if pos >= len(model) { return mj_fail("truncated model-ir path color") }
			color := model[pos]; pos += 1
			inertia := mj_read_u32(model, &pos, &ok) != 0
			longest := mj_read_u32(model, &pos, &ok) != 0
			edges := mj_read_u32(model, &pos, &ok) != 0
			vertices := mj_read_u32(model, &pos, &ok) != 0
			if !ok { return mj_fail("invalid model-ir path flags") }
			current_path = Path_State{start = grid_wave_string(target_grid, from_string), finish = grid_wave_string(target_grid, to_string), substrate = grid_wave_string(target_grid, on_string), value = grid_value(target_grid, color), inertia = inertia, longest = longest, edges = edges, vertices = vertices}
			current_has_path = true
		} else if op == 1 {
			if pos + 2 > len(model) { return mj_fail("truncated one-cell replace rule") }
			input_index := int(model[pos]); output_index := int(model[pos + 1]); pos += 2
			if input_index >= values_len || output_index >= values_len { return mj_fail("one-cell rule value index out of range") }
			in_chars := []u8{values[input_index]}
			out_chars := []u8{values[output_index]}
			base := rule_from_char_arrays(&g, in_chars, 1, 1, 1, out_chars, 1, 1, 1)
			append_rule_symmetries(&g, &rules, base, "()")
		} else if op == 2 {
			imx := int(mj_read_u32(model, &pos, &ok)); imy := int(mj_read_u32(model, &pos, &ok)); imz := int(mj_read_u32(model, &pos, &ok))
			omx := int(mj_read_u32(model, &pos, &ok)); omy := int(mj_read_u32(model, &pos, &ok)); omz := int(mj_read_u32(model, &pos, &ok))
			probability := mj_read_f64(model, &pos, &ok)
			symmetry_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || imx <= 0 || imy <= 0 || imz <= 0 || omx <= 0 || omy <= 0 || omz <= 0 || symmetry_len < 0 { return mj_fail("invalid pattern rule header") }
			if pos + symmetry_len > len(model) { return mj_fail("truncated pattern rule symmetry") }
			symmetry := string(model[pos:pos + symmetry_len]); pos += symmetry_len
			input_len := imx * imy * imz
			output_len := omx * omy * omz
			if pos + input_len + output_len > len(model) { return mj_fail("truncated pattern rule data") }
			input_chars := model[pos:pos + input_len]; pos += input_len
			output_chars := model[pos:pos + output_len]; pos += output_len
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			base := rule_from_char_arrays(target_grid, input_chars, imx, imy, imz, output_chars, omx, omy, omz, probability)
			append_rule_symmetries(target_grid, &rules, base, symmetry)
		} else {
			return mj_fail("unsupported model-ir rule opcode")
		}
	}

	if node_open || len(rules) > node_start || current_fields != nil || current_observations != nil || current_search || current_has_path || current_has_convolution || current_has_convchain || current_has_wfc || current_has_map {
		flush_node(&nodes, node_kind, node_start, len(rules) - node_start, node_steps, &current_fields, &current_observations, &current_potentials, &current_future, &current_search, &current_limit, &current_depth_coefficient, &current_path, &current_has_path, &current_convolution, &current_has_convolution, &current_convchain, &current_has_convchain, &current_wfc, &current_has_wfc, &current_map, &current_has_map, &current_temperature)
	}
	if len(container_stack) != 0 { return mj_fail("model-ir unclosed container") }
	if len(rules) == 0 {
		has_executable := false
		for n in nodes do if (n.kind == 6 && n.has_path) || (n.kind == 7 && n.has_convolution) || (n.kind == 8 && n.has_convchain) || (n.kind == 9 && n.has_wfc) || (n.kind == 10 && n.has_map) { has_executable = true }
		if !has_executable { return mj_fail("model-ir contains no rules") }
	}
	if len(nodes) == 0 { append(&nodes, MJ_Node{kind = node_kind, start = 0, count = len(rules)}) }

	random := mj_random_init(i32(seed & 0x7fffffff))
	steps_run := 0
	changed := false
	if container_kind == 4 {
		steps_run, changed = mj_run_markov_nodes_with_count(&g, rules[:], nodes[:], &random, int(max_steps))
	} else if container_kind == 5 {
		steps_run, changed = mj_run_sequence_nodes_with_count(&g, rules[:], nodes[:], &random, int(max_steps))
	} else {
		node := &nodes[0]
		steps_run, changed = mj_run_node_with_count(&g, node, rules[node.start:node.start + node.count], &random, int(max_steps))
	}
	output_grid := mj_output_grid_for_csharp_timing(&g, nodes[:])
	done := !mj_any_one_match(output_grid, rules[:])

	return mj_respond_grid(output_grid, u32(steps_run), changed, done)
}

mj_session_create_mjir_v1 :: proc(model: []u8, initial: []u8, width, height, depth: u32, seed: u64) -> rawptr {
	if len(model) < 20 { _ = mj_fail("model-ir is too short"); return nil }
	if model[0] != 'M' || model[1] != 'J' || model[2] != 'I' || model[3] != 'R' { _ = mj_fail("model-ir magic mismatch"); return nil }
	pos := 4
	ok := true
	version := mj_read_u32(model, &pos, &ok)
	if !ok || version != 1 { _ = mj_fail("unsupported model-ir version"); return nil }
	values_len := int(mj_read_u32(model, &pos, &ok))
	if !ok || values_len <= 0 || pos + values_len > len(model) { _ = mj_fail("invalid model-ir values"); return nil }
	values_start := pos
	values := string(model[values_start:values_start + values_len])
	pos += values_len
	rule_count := int(mj_read_u32(model, &pos, &ok))
	if !ok || rule_count <= 0 { _ = mj_fail("invalid model-ir rule count"); return nil }

	cell_count_u64 := u64(width) * u64(height) * u64(depth)
	if cell_count_u64 > u64(len(initial)) { _ = mj_fail("initial-cells shorter than configured grid"); return nil }
	cell_count := int(cell_count_u64)
	if cell_count > MJ_OUTPUT_CAPACITY { _ = mj_fail("grid too large for MVP output buffer"); return nil }

	g := grid_init(int(width), int(height), int(depth), values, false)
	copy(g.state, initial[:cell_count])

	rules := make([dynamic]Rule)
	nodes := make([dynamic]MJ_Node)
	container_kind: u32 = 0
	node_kind: u32 = 1
	node_steps := 0
	node_start := 0
	node_open := false
	container_stack := make([dynamic]int)
	current_fields: []Field_State
	current_potentials: []int
	current_observations: []Observation_State
	current_future: []i32
	current_search := false
	current_limit := -1
	current_depth_coefficient := 0.5
	current_path: Path_State
	current_has_path := false
	current_convolution: Convolution_State
	current_has_convolution := false
	current_convchain: ConvChain_State
	current_has_convchain := false
	current_wfc: WFC_State
	current_has_wfc := false
	current_map: Map_State
	current_has_map := false
	current_temperature := 0.0
	flush_node :: proc(nodes: ^[dynamic]MJ_Node, kind: u32, start, count, steps: int, fields: ^[]Field_State, observations: ^[]Observation_State, potentials: ^[]int, future: ^[]i32, search: ^bool, limit: ^int, depth_coefficient: ^f64, path: ^Path_State, has_path: ^bool, convolution: ^Convolution_State, has_convolution: ^bool, convchain: ^ConvChain_State, has_convchain: ^bool, wfc: ^WFC_State, has_wfc: ^bool, map_state: ^Map_State, has_map: ^bool, temperature: ^f64) {
		append(nodes, MJ_Node{kind = kind, start = start, count = count, steps = steps, fields = fields^, observations = observations^, potentials = potentials^, future = future^, search = search^, limit = limit^, depth_coefficient = depth_coefficient^, path = path^, has_path = has_path^, convolution = convolution^, has_convolution = has_convolution^, convchain = convchain^, has_convchain = has_convchain^, wfc = wfc^, has_wfc = has_wfc^, map_state = map_state^, has_map = has_map^, temperature = temperature^})
		fields^ = nil
		observations^ = nil
		potentials^ = nil
		future^ = nil
		search^ = false
		limit^ = -1
		depth_coefficient^ = 0.5
		path^ = {}
		has_path^ = false
		convolution^ = {}
		has_convolution^ = false
		convchain^ = {}
		has_convchain^ = false
		wfc^ = {}
		has_wfc^ = false
		map_state^ = {}
		has_map^ = false
		temperature^ = 0
	}
	root_marker_seen := false
	for _ in 0..<rule_count {
		op := mj_read_u32(model, &pos, &ok)
		if !ok { _ = mj_fail("truncated model-ir rule opcode"); return nil }
		if op == 100 {
			kind := mj_read_u32(model, &pos, &ok)
			marker_steps := int(mj_read_u32(model, &pos, &ok))
			if !ok || kind < 1 || kind > 10 { _ = mj_fail("invalid model-ir node kind"); return nil }
			is_container_kind := kind == 4 || kind == 5 || kind == 9 || kind == 10
			if (kind == 4 || kind == 5) && !root_marker_seen && len(nodes) == 0 && !node_open {
				container_kind = kind
				root_marker_seen = true
			} else if is_container_kind {
				if node_open || len(rules) > node_start || current_fields != nil || current_observations != nil || current_search || current_has_path || current_has_convolution || current_has_convchain || current_has_wfc || current_has_map {
					flush_node(&nodes, node_kind, node_start, len(rules) - node_start, node_steps, &current_fields, &current_observations, &current_potentials, &current_future, &current_search, &current_limit, &current_depth_coefficient, &current_path, &current_has_path, &current_convolution, &current_has_convolution, &current_convchain, &current_has_convchain, &current_wfc, &current_has_wfc, &current_map, &current_has_map, &current_temperature)
					node_open = false
				}
				node_start = len(rules)
				node_steps = 0
				container_index := len(nodes)
				append(&nodes, MJ_Node{kind = kind, steps = marker_steps, children_start = container_index + 1})
				append(&container_stack, container_index)
			} else {
				if node_open || len(rules) > node_start || current_fields != nil || current_observations != nil || current_search || current_has_path || current_has_convolution || current_has_convchain || current_has_wfc || current_has_map {
					flush_node(&nodes, node_kind, node_start, len(rules) - node_start, node_steps, &current_fields, &current_observations, &current_potentials, &current_future, &current_search, &current_limit, &current_depth_coefficient, &current_path, &current_has_path, &current_convolution, &current_has_convolution, &current_convchain, &current_has_convchain, &current_wfc, &current_has_wfc, &current_map, &current_has_map, &current_temperature)
				}
				node_kind = kind
				node_steps = marker_steps
				node_start = len(rules)
				node_open = true
				root_marker_seen = true
			}
		} else if op == 101 {
			if pos >= len(model) { _ = mj_fail("truncated model-ir union symbol"); return nil }
			symbol := model[pos]; pos += 1
			union_values_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || union_values_len <= 0 || pos + union_values_len > len(model) { _ = mj_fail("invalid model-ir union values"); return nil }
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			grid_add_union(target_grid, symbol, string(model[pos:pos + union_values_len]))
			pos += union_values_len
		} else if op == 102 {
			if node_open || len(rules) > node_start || current_fields != nil || current_observations != nil || current_search || current_has_path || current_has_convolution || current_has_convchain || current_has_wfc || current_has_map {
				flush_node(&nodes, node_kind, node_start, len(rules) - node_start, node_steps, &current_fields, &current_observations, &current_potentials, &current_future, &current_search, &current_limit, &current_depth_coefficient, &current_path, &current_has_path, &current_convolution, &current_has_convolution, &current_convchain, &current_has_convchain, &current_wfc, &current_has_wfc, &current_map, &current_has_map, &current_temperature)
				node_open = false
			}
			if len(container_stack) == 0 { _ = mj_fail("model-ir container end without start"); return nil }
			container_index := container_stack[len(container_stack) - 1]
			_ = pop(&container_stack)
			nodes[container_index].children_count = len(nodes) - nodes[container_index].children_start
			node_start = len(rules)
			node_steps = 0
		} else if op == 103 {
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			if pos >= len(model) { _ = mj_fail("truncated model-ir field symbol"); return nil }
			for_symbol := model[pos]; pos += 1
			recompute := mj_read_u32(model, &pos, &ok) != 0
			essential := mj_read_u32(model, &pos, &ok) != 0
			to_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || to_len < 0 || pos + to_len > len(model) { _ = mj_fail("invalid model-ir field to"); return nil }
			to_string := string(model[pos:pos + to_len]); pos += to_len
			from_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || from_len < 0 || pos + from_len > len(model) { _ = mj_fail("invalid model-ir field from"); return nil }
			from_string := string(model[pos:pos + from_len]); pos += from_len
			on_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || on_len <= 0 || pos + on_len > len(model) { _ = mj_fail("invalid model-ir field on"); return nil }
			on_string := string(model[pos:pos + on_len]); pos += on_len
			if current_fields == nil {
				current_fields = make([]Field_State, len(target_grid.characters))
				current_potentials = make([]int, len(target_grid.state) * len(target_grid.characters))
			}
			field := Field_State{present = true, recompute = recompute, essential = essential, substrate = grid_wave_string(target_grid, on_string)}
			if from_len > 0 {
				field.inversed = true
				field.zero = grid_wave_string(target_grid, from_string)
			} else {
				field.zero = grid_wave_string(target_grid, to_string)
			}
			current_fields[grid_value(target_grid, for_symbol)] = field
		} else if op == 104 {
			current_temperature = mj_read_f64(model, &pos, &ok)
			if !ok { _ = mj_fail("invalid model-ir temperature"); return nil }
		} else if op == 105 {
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			if pos >= len(model) { _ = mj_fail("truncated model-ir observe value"); return nil }
			observe_value := model[pos]; pos += 1
			from_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || from_len < 0 || pos + from_len > len(model) { _ = mj_fail("invalid model-ir observe from"); return nil }
			from_string := string(model[pos:pos + from_len]); pos += from_len
			to_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || to_len <= 0 || pos + to_len > len(model) { _ = mj_fail("invalid model-ir observe to"); return nil }
			to_string := string(model[pos:pos + to_len]); pos += to_len
			if current_observations == nil {
				current_observations = make([]Observation_State, len(target_grid.characters))
				if !current_search do current_potentials = make([]int, len(target_grid.state) * len(target_grid.characters))
				current_future = make([]i32, len(target_grid.state))
			}
			from_value := observe_value
			if from_len > 0 do from_value = from_string[0]
			current_observations[grid_value(target_grid, observe_value)] = Observation_State{present = true, from = grid_value(target_grid, from_value), to = grid_wave_string(target_grid, to_string)}
		} else if op == 111 {
			current_search = mj_read_u32(model, &pos, &ok) != 0
			limit_raw := mj_read_u32(model, &pos, &ok)
			if limit_raw == 0xffffffff { current_limit = -1 } else { current_limit = int(limit_raw) }
			current_depth_coefficient = mj_read_f64(model, &pos, &ok)
			if !ok { _ = mj_fail("invalid model-ir search config"); return nil }
		} else if op == 107 {
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			neighborhood_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || neighborhood_len < 0 || pos + neighborhood_len > len(model) { _ = mj_fail("invalid model-ir convolution neighborhood"); return nil }
			neighborhood := string(model[pos:pos + neighborhood_len]); pos += neighborhood_len
			periodic := mj_read_u32(model, &pos, &ok) != 0
			rule_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || rule_len <= 0 { _ = mj_fail("invalid model-ir convolution rule count"); return nil }
			current_convolution = Convolution_State{kernel = convolution_kernel(target_grid.mz == 1, neighborhood), periodic = periodic, c = len(target_grid.characters), sumfield = make([]int, len(target_grid.state) * len(target_grid.characters)), steps = node_steps}
			for _r in 0..<rule_len {
				if pos + 2 > len(model) { _ = mj_fail("truncated model-ir convolution rule symbols"); return nil }
				input := model[pos]; output := model[pos + 1]; pos += 2
				probability := mj_read_f64(model, &pos, &ok)
				values_len := int(mj_read_u32(model, &pos, &ok))
				if !ok || values_len < 0 || pos + values_len > len(model) { _ = mj_fail("invalid model-ir convolution values"); return nil }
				values_string := string(model[pos:pos + values_len]); pos += values_len
				sum_len := int(mj_read_u32(model, &pos, &ok))
				if !ok || sum_len < 0 || pos + sum_len > len(model) { _ = mj_fail("invalid model-ir convolution sum"); return nil }
				sum_string := string(model[pos:pos + sum_len]); pos += sum_len
				rule := Convolution_Rule{input = grid_value(target_grid, input), output = grid_value(target_grid, output), p = probability, sums = mj_convolution_sums_from_string(sum_string)}
				for i in 0..<len(values_string) do append(&rule.values, grid_value(target_grid, values_string[i]))
				append(&current_convolution.rules, rule)
			}
			current_has_convolution = true
		} else if op == 108 {
			n := int(mj_read_u32(model, &pos, &ok))
			temperature := mj_read_f64(model, &pos, &ok)
			if pos + 3 > len(model) { _ = mj_fail("truncated model-ir convchain symbols"); return nil }
			black := model[pos]; white := model[pos + 1]; on := model[pos + 2]; pos += 3
			weights_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || n <= 0 || weights_len != (1 << uint(n * n)) { _ = mj_fail("invalid model-ir convchain header"); return nil }
			if pos + weights_len * 8 > len(model) { _ = mj_fail("truncated model-ir convchain weights"); return nil }
			weights := make([]f64, weights_len)
			for i in 0..<weights_len do weights[i] = mj_read_f64(model, &pos, &ok)
			if !ok { _ = mj_fail("invalid model-ir convchain weights"); return nil }
			current_convchain = ConvChain_State{n = n, steps = node_steps, temperature = temperature, c0 = grid_value(&g, black), c1 = grid_value(&g, white), substrate_color = grid_value(&g, on), substrate = make([]bool, len(g.state)), weights = weights}
			current_has_convchain = true
		} else if op == 109 {
			n := int(mj_read_u32(model, &pos, &ok))
			periodic := mj_read_u32(model, &pos, &ok) != 0
			shannon := mj_read_u32(model, &pos, &ok) != 0
			tries := int(mj_read_u32(model, &pos, &ok))
			new_values_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || n <= 0 || new_values_len <= 0 || pos + new_values_len > len(model) { _ = mj_fail("invalid model-ir wfc header"); return nil }
			new_values := string(model[pos:pos + new_values_len]); pos += new_values_len
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			p_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || p_count <= 0 { _ = mj_fail("invalid model-ir wfc pattern count"); return nil }
			pattern_len := n * n
			current_wfc = WFC_State{counter = -1, n = n, p = p_count, periodic = periodic, shannon = shannon, tries = tries, newgrid = grid_init(target_grid.mx, target_grid.my, target_grid.mz, new_values, false)}
			current_wfc.patterns = make([][]u8, p_count)
			current_wfc.weights = make([]f64, p_count)
			for pidx in 0..<p_count {
				current_wfc.weights[pidx] = mj_read_f64(model, &pos, &ok)
				if !ok || pos + pattern_len > len(model) { _ = mj_fail("invalid model-ir wfc pattern"); return nil }
				current_wfc.patterns[pidx] = make([]u8, pattern_len)
				copy(current_wfc.patterns[pidx], model[pos:pos + pattern_len]); pos += pattern_len
			}
			dirs := int(mj_read_u32(model, &pos, &ok))
			if !ok || dirs <= 0 { _ = mj_fail("invalid model-ir wfc propagator"); return nil }
			current_wfc.propagator = make([][][]int, dirs)
			for d in 0..<dirs {
				current_wfc.propagator[d] = make([][]int, p_count)
				for pidx in 0..<p_count {
					list_len := int(mj_read_u32(model, &pos, &ok))
					if !ok || list_len < 0 { _ = mj_fail("invalid model-ir wfc propagator list"); return nil }
					current_wfc.propagator[d][pidx] = make([]int, list_len)
					for i in 0..<list_len do current_wfc.propagator[d][pidx][i] = int(mj_read_u32(model, &pos, &ok))
				}
			}
			map_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || map_count <= 0 { _ = mj_fail("invalid model-ir wfc map count"); return nil }
			for _m in 0..<map_count {
				if pos >= len(model) { _ = mj_fail("truncated model-ir wfc map input"); return nil }
				input := model[pos]; pos += 1
				if pos + p_count > len(model) { _ = mj_fail("truncated model-ir wfc map positions"); return nil }
				positions := make([]bool, p_count)
				for i in 0..<p_count { positions[i] = model[pos] != 0; pos += 1 }
				append(&current_wfc.map_values, grid_value(target_grid, input))
				append(&current_wfc.map_positions, positions)
			}
			if !ok { _ = mj_fail("invalid model-ir wfc payload"); return nil }
			wfc_base_finish(&current_wfc, target_grid)
			if len(container_stack) > 0 && nodes[container_stack[len(container_stack) - 1]].kind == 9 {
				wfc_index := container_stack[len(container_stack) - 1]
				nodes[wfc_index].wfc = current_wfc
				nodes[wfc_index].has_wfc = true
				current_wfc = {}
			} else {
				current_has_wfc = true
			}
		} else if op == 112 {
			tile_s := int(mj_read_u32(model, &pos, &ok))
			tile_sz := int(mj_read_u32(model, &pos, &ok))
			overlap_raw := mj_read_u32(model, &pos, &ok)
			overlapz_raw := mj_read_u32(model, &pos, &ok)
			overlap := int(overlap_raw)
			overlapz := int(overlapz_raw)
			if overlap_raw > 0x7fffffff do overlap = int(i64(overlap_raw) - i64(0x100000000))
			if overlapz_raw > 0x7fffffff do overlapz = int(i64(overlapz_raw) - i64(0x100000000))
			periodic := mj_read_u32(model, &pos, &ok) != 0
			shannon := mj_read_u32(model, &pos, &ok) != 0
			tries := int(mj_read_u32(model, &pos, &ok))
			new_values_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || tile_s <= 0 || tile_sz <= 0 || new_values_len <= 0 || pos + new_values_len > len(model) { _ = mj_fail("invalid model-ir tile wfc header"); return nil }
			new_values := string(model[pos:pos + new_values_len]); pos += new_values_len
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			p_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || p_count <= 0 { _ = mj_fail("invalid model-ir tile wfc pattern count"); return nil }
			pattern_len := tile_s * tile_s * tile_sz
			mx2 := (tile_s - overlap) * target_grid.mx + overlap
			my2 := (tile_s - overlap) * target_grid.my + overlap
			mz2 := (tile_sz - overlapz) * target_grid.mz + overlapz
			current_wfc = WFC_State{counter = -1, n = 1, p = p_count, periodic = periodic, shannon = shannon, tries = tries, tile_mode = true, tile_s = tile_s, tile_sz = tile_sz, overlap = overlap, overlapz = overlapz, newgrid = grid_init(mx2, my2, mz2, new_values, false)}
			current_wfc.patterns = make([][]u8, p_count)
			current_wfc.weights = make([]f64, p_count)
			for pidx in 0..<p_count {
				current_wfc.weights[pidx] = mj_read_f64(model, &pos, &ok)
				if !ok || pos + pattern_len > len(model) { _ = mj_fail("invalid model-ir tile wfc pattern"); return nil }
				current_wfc.patterns[pidx] = make([]u8, pattern_len)
				copy(current_wfc.patterns[pidx], model[pos:pos + pattern_len]); pos += pattern_len
			}
			dirs := int(mj_read_u32(model, &pos, &ok))
			if !ok || dirs <= 0 { _ = mj_fail("invalid model-ir tile wfc propagator"); return nil }
			current_wfc.propagator = make([][][]int, dirs)
			for d in 0..<dirs {
				current_wfc.propagator[d] = make([][]int, p_count)
				for pidx in 0..<p_count {
					list_len := int(mj_read_u32(model, &pos, &ok))
					if !ok || list_len < 0 { _ = mj_fail("invalid model-ir tile wfc propagator list"); return nil }
					current_wfc.propagator[d][pidx] = make([]int, list_len)
					for i in 0..<list_len do current_wfc.propagator[d][pidx][i] = int(mj_read_u32(model, &pos, &ok))
				}
			}
			map_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || map_count <= 0 { _ = mj_fail("invalid model-ir tile wfc map count"); return nil }
			for _m in 0..<map_count {
				if pos >= len(model) { _ = mj_fail("truncated model-ir tile wfc map input"); return nil }
				input_char := model[pos]; pos += 1
				if pos + p_count > len(model) { _ = mj_fail("truncated model-ir tile wfc map positions"); return nil }
				positions := make([]bool, p_count)
				for i in 0..<p_count { positions[i] = model[pos] != 0; pos += 1 }
				input := u8(0)
				if input_char != 0 do input = grid_value(target_grid, input_char)
				append(&current_wfc.map_values, input)
				append(&current_wfc.map_positions, positions)
			}
			if !ok { _ = mj_fail("invalid model-ir tile wfc payload"); return nil }
			wfc_base_finish(&current_wfc, target_grid)
			if len(container_stack) > 0 && nodes[container_stack[len(container_stack) - 1]].kind == 9 {
				wfc_index := container_stack[len(container_stack) - 1]
				nodes[wfc_index].wfc = current_wfc
				nodes[wfc_index].has_wfc = true
				current_wfc = {}
			} else {
				current_has_wfc = true
			}
		} else if op == 110 {
			nx := int(mj_read_u32(model, &pos, &ok)); dx := int(mj_read_u32(model, &pos, &ok))
			ny := int(mj_read_u32(model, &pos, &ok)); dy := int(mj_read_u32(model, &pos, &ok))
			nz := int(mj_read_u32(model, &pos, &ok)); dz := int(mj_read_u32(model, &pos, &ok))
			values_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || nx <= 0 || dx <= 0 || ny <= 0 || dy <= 0 || nz <= 0 || dz <= 0 || values_len <= 0 || pos + values_len > len(model) { _ = mj_fail("invalid model-ir map header"); return nil }
			map_values := string(model[pos:pos + values_len]); pos += values_len
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			current_map = Map_State{nx = nx, dx = dx, ny = ny, dy = dy, nz = nz, dz = dz, grid = grid_init(target_grid.mx * nx / dx, target_grid.my * ny / dy, target_grid.mz * nz / dz, map_values, false)}
			union_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || union_count < 0 { _ = mj_fail("invalid model-ir map union count"); return nil }
			for _u in 0..<union_count {
				if pos >= len(model) { _ = mj_fail("truncated model-ir map union symbol"); return nil }
				symbol := model[pos]; pos += 1
				ulen := int(mj_read_u32(model, &pos, &ok))
				if !ok || ulen < 0 || pos + ulen > len(model) { _ = mj_fail("truncated model-ir map union values"); return nil }
				grid_add_union(&current_map.grid, symbol, string(model[pos:pos + ulen])); pos += ulen
			}
			rule_count := int(mj_read_u32(model, &pos, &ok))
			if !ok || rule_count <= 0 { _ = mj_fail("invalid model-ir map rule count"); return nil }
			for _r in 0..<rule_count {
				imx := int(mj_read_u32(model, &pos, &ok)); imy := int(mj_read_u32(model, &pos, &ok)); imz := int(mj_read_u32(model, &pos, &ok))
				omx := int(mj_read_u32(model, &pos, &ok)); omy := int(mj_read_u32(model, &pos, &ok)); omz := int(mj_read_u32(model, &pos, &ok))
				probability := mj_read_f64(model, &pos, &ok)
				symmetry_len := int(mj_read_u32(model, &pos, &ok))
				if !ok || imx <= 0 || imy <= 0 || imz <= 0 || omx <= 0 || omy <= 0 || omz <= 0 || symmetry_len < 0 { _ = mj_fail("invalid model-ir map rule header"); return nil }
				if pos + symmetry_len > len(model) { _ = mj_fail("truncated model-ir map rule symmetry"); return nil }
				symmetry := string(model[pos:pos + symmetry_len]); pos += symmetry_len
				input_len := imx * imy * imz
				output_len := omx * omy * omz
				if pos + input_len + output_len > len(model) { _ = mj_fail("truncated model-ir map rule data"); return nil }
				input_chars := model[pos:pos + input_len]; pos += input_len
				output_chars := model[pos:pos + output_len]; pos += output_len
				base := rule_from_char_arrays_grids(target_grid, &current_map.grid, input_chars, imx, imy, imz, output_chars, omx, omy, omz, probability)
				append_rule_symmetries(&current_map.grid, &current_map.rules, base, symmetry)
			}
			if len(container_stack) > 0 && nodes[container_stack[len(container_stack) - 1]].kind == 10 {
				map_index := container_stack[len(container_stack) - 1]
				nodes[map_index].map_state = current_map
				nodes[map_index].has_map = true
				current_map = {}
			} else {
				current_has_map = true
			}
		} else if op == 106 {
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			from_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || from_len <= 0 || pos + from_len > len(model) { _ = mj_fail("invalid model-ir path from"); return nil }
			from_string := string(model[pos:pos + from_len]); pos += from_len
			to_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || to_len <= 0 || pos + to_len > len(model) { _ = mj_fail("invalid model-ir path to"); return nil }
			to_string := string(model[pos:pos + to_len]); pos += to_len
			on_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || on_len <= 0 || pos + on_len > len(model) { _ = mj_fail("invalid model-ir path on"); return nil }
			on_string := string(model[pos:pos + on_len]); pos += on_len
			if pos >= len(model) { _ = mj_fail("truncated model-ir path color"); return nil }
			color := model[pos]; pos += 1
			inertia := mj_read_u32(model, &pos, &ok) != 0
			longest := mj_read_u32(model, &pos, &ok) != 0
			edges := mj_read_u32(model, &pos, &ok) != 0
			vertices := mj_read_u32(model, &pos, &ok) != 0
			if !ok { _ = mj_fail("invalid model-ir path flags"); return nil }
			current_path = Path_State{start = grid_wave_string(target_grid, from_string), finish = grid_wave_string(target_grid, to_string), substrate = grid_wave_string(target_grid, on_string), value = grid_value(target_grid, color), inertia = inertia, longest = longest, edges = edges, vertices = vertices}
			current_has_path = true
		} else if op == 1 {
			if pos + 2 > len(model) { _ = mj_fail("truncated one-cell replace rule"); return nil }
			input_index := int(model[pos]); output_index := int(model[pos + 1]); pos += 2
			if input_index >= values_len || output_index >= values_len { _ = mj_fail("one-cell rule value index out of range"); return nil }
			in_chars := []u8{values[input_index]}
			out_chars := []u8{values[output_index]}
			base := rule_from_char_arrays(&g, in_chars, 1, 1, 1, out_chars, 1, 1, 1)
			append_rule_symmetries(&g, &rules, base, "()")
		} else if op == 2 {
			imx := int(mj_read_u32(model, &pos, &ok)); imy := int(mj_read_u32(model, &pos, &ok)); imz := int(mj_read_u32(model, &pos, &ok))
			omx := int(mj_read_u32(model, &pos, &ok)); omy := int(mj_read_u32(model, &pos, &ok)); omz := int(mj_read_u32(model, &pos, &ok))
			probability := mj_read_f64(model, &pos, &ok)
			symmetry_len := int(mj_read_u32(model, &pos, &ok))
			if !ok || imx <= 0 || imy <= 0 || imz <= 0 || omx <= 0 || omy <= 0 || omz <= 0 || symmetry_len < 0 { _ = mj_fail("invalid pattern rule header"); return nil }
			if pos + symmetry_len > len(model) { _ = mj_fail("truncated pattern rule symmetry"); return nil }
			symmetry := string(model[pos:pos + symmetry_len]); pos += symmetry_len
			input_len := imx * imy * imz
			output_len := omx * omy * omz
			if pos + input_len + output_len > len(model) { _ = mj_fail("truncated pattern rule data"); return nil }
			input_chars := model[pos:pos + input_len]; pos += input_len
			output_chars := model[pos:pos + output_len]; pos += output_len
			target_grid := &g
			for si := len(container_stack) - 1; si >= 0; si -= 1 {
				candidate := container_stack[si]
				if nodes[candidate].kind == 10 && nodes[candidate].has_map {
					target_grid = &nodes[candidate].map_state.grid
					break
				}
				if nodes[candidate].kind == 9 && nodes[candidate].has_wfc {
					target_grid = &nodes[candidate].wfc.newgrid
					break
				}
				if si == 0 do break
			}
			base := rule_from_char_arrays(target_grid, input_chars, imx, imy, imz, output_chars, omx, omy, omz, probability)
			append_rule_symmetries(target_grid, &rules, base, symmetry)
		} else {
			{ _ = mj_fail("unsupported model-ir rule opcode"); return nil }
		}
	}

	if node_open || len(rules) > node_start || current_fields != nil || current_observations != nil || current_search || current_has_path || current_has_convolution || current_has_convchain || current_has_wfc || current_has_map {
		flush_node(&nodes, node_kind, node_start, len(rules) - node_start, node_steps, &current_fields, &current_observations, &current_potentials, &current_future, &current_search, &current_limit, &current_depth_coefficient, &current_path, &current_has_path, &current_convolution, &current_has_convolution, &current_convchain, &current_has_convchain, &current_wfc, &current_has_wfc, &current_map, &current_has_map, &current_temperature)
	}
	if len(container_stack) != 0 { _ = mj_fail("model-ir unclosed container"); return nil }
	if len(rules) == 0 {
		has_executable := false
		for n in nodes do if (n.kind == 6 && n.has_path) || (n.kind == 7 && n.has_convolution) || (n.kind == 8 && n.has_convchain) || (n.kind == 9 && n.has_wfc) || (n.kind == 10 && n.has_map) { has_executable = true }
		if !has_executable { _ = mj_fail("model-ir contains no rules"); return nil }
	}
	if len(nodes) == 0 { append(&nodes, MJ_Node{kind = node_kind, start = 0, count = len(rules)}) }

	delete(container_stack)
	s := new(MJ_Runtime_Session)
	s.g = g
	s.rules = rules
	s.nodes = nodes
	for i in 0..<len(s.nodes) {
		if s.nodes[i].has_wfc do s.nodes[i].wfc.preview_updates = true
	}
	s.container_kind = container_kind
	s.random = mj_random_init(i32(seed & 0x7fffffff))
	s.states = mj_prepare_node_states(&s.g, s.nodes[:])
	s.counters = make([]int, len(s.nodes))
	s.positions = make([]int, len(s.nodes))
	s.active = make([]int, len(s.nodes) + 1)
	s.changes = make([dynamic]Cell)
	s.first = make([dynamic]int)
	append(&s.first, 0)
	s.child = 0
	s.steps_run = 0
	s.done = false
	_ = mj_respond_grid(&s.g, 0, false, false)
	return rawptr(s)
}

mj_session_step_runtime :: proc(s: ^MJ_Runtime_Session, steps: u32) -> (u32, bool, bool) {
	if s.done do return 0, false, true
	counter := 0
	changed_any := false
	if s.container_kind == 4 {
		for steps == 0 || counter < int(steps) {
			changed := mj_markov_range_go(&s.g, s.rules[:], s.nodes[:], 0, len(s.nodes), &s.random, s.states, s.counters, s.positions, s.active, &s.changes, &s.first, int(s.steps_run) + counter, -1)
			if !changed { s.done = true; break }
			changed_any = true
			counter += 1
			append(&s.first, len(s.changes))
		}
	} else if s.container_kind == 5 {
		for s.child < len(s.nodes) && (steps == 0 || counter < int(steps)) {
			changed := mj_sequence_range_go(&s.g, s.rules[:], s.nodes[:], 0, len(s.nodes), &s.random, s.states, s.counters, s.positions, s.active, &s.changes, &s.first, int(s.steps_run) + counter, &s.child)
			if changed do changed_any = true
			counter += 1
			append(&s.first, len(s.changes))
			if !changed {
				if s.child < 0 {
					s.child = -s.child - 1
					continue
				}
				if !(steps > 0 && len(s.nodes) == 1 + s.nodes[0].children_count && s.nodes[0].kind >= 4) {
					s.done = true
					break
				}
			}
		}
		if s.child >= len(s.nodes) do s.done = true
	} else {
		node := &s.nodes[0]
		run, changed := mj_run_node_with_count(&s.g, node, s.rules[node.start:node.start + node.count], &s.random, int(steps))
		counter = run
		changed_any = changed
		if !changed do s.done = true
	}
	s.steps_run += u32(counter)
	output_grid := mj_output_grid_for_csharp_timing(&s.g, s.nodes[:])
	if s.container_kind != 5 && (!changed_any || !mj_any_one_match(output_grid, s.rules[:])) {
		s.done = true
	}
	return u32(counter), changed_any, s.done
}

mj_session_destroy_runtime :: proc(s: ^MJ_Runtime_Session) {
	if s == nil do return
	grid_destroy(&s.g)
	for i in 0..<len(s.rules) { rule_destroy(&s.rules[i]) }
	delete(s.rules)
	for i in 0..<len(s.nodes) {
		if s.nodes[i].fields != nil do delete(s.nodes[i].fields)
		if s.nodes[i].observations != nil do delete(s.nodes[i].observations)
		if s.nodes[i].potentials != nil do delete(s.nodes[i].potentials)
		if s.nodes[i].future != nil do delete(s.nodes[i].future)
		if s.nodes[i].trajectory != nil do search_destroy_trajectory(s.nodes[i].trajectory)
		if s.nodes[i].has_convolution do convolution_destroy(&s.nodes[i].convolution)
		if s.nodes[i].has_convchain do convchain_destroy(&s.nodes[i].convchain)
		if s.nodes[i].has_wfc do wfc_destroy(&s.nodes[i].wfc)
		if s.nodes[i].has_map do map_destroy(&s.nodes[i].map_state)
	}
	delete(s.nodes)
	if s.states != nil do mj_destroy_node_states(s.states)
	if s.counters != nil do delete(s.counters)
	if s.positions != nil do delete(s.positions)
	if s.active != nil do delete(s.active)
	if s.changes != nil do delete(s.changes)
	if s.first != nil do delete(s.first)
	free(s)
}

mj_output_grid_for_csharp_timing :: proc(g: ^Grid, nodes: []MJ_Node) -> ^Grid {
	for i in 0..<len(nodes) {
		n := &nodes[i]
		if n.kind == 9 && n.has_wfc && n.wfc.tile_mode && !n.wfc.firstgo && n.wfc.counter < 0 {
			return &n.wfc.newgrid
		}
	}
	return g
}

mj_run_node_with_count :: proc(g: ^Grid, node: ^MJ_Node, rules: []Rule, random: ^MJRandom, steps: int) -> (int, bool) {
	if node.kind == 6 {
		changes := make([dynamic]Cell)
		defer delete(changes)
		changed := path_go(&node.path, g, random, &changes)
		if changed do return 1, true
		return 0, false
	}
	if node.kind == 7 {
		changed := false
		counter := 0
		for steps <= 0 || counter < steps {
			if !convolution_go(&node.convolution, g, random) do break
			changed = true
			counter += 1
		}
		return counter, changed
	}
	if node.kind == 8 {
		changed := false
		counter := 0
		for steps <= 0 || counter < steps {
			if !convchain_go(&node.convchain, g, random) do break
			changed = true
			counter += 1
		}
		return counter, changed
	}
	if node.kind == 9 {
		changed := wfc_go(&node.wfc, g, random)
		if changed do return 1, true
		return 0, false
	}
	if node.kind == 10 {
		if node.map_state.mapped do return 0, false
		map_go_initial(&node.map_state, g)
		return 1, true
	}
	if node.kind == 1 && node.potentials != nil do return mj_run_one_node_with_fields_count(g, node, rules, random, steps)
	if node.kind == 2 && node.potentials != nil do return mj_run_all_node_with_fields_count(g, node, rules, random, steps)
	return mj_run_node_rules_with_count(g, node.kind, rules, random, steps)
}

mj_run_node_rules_with_count :: proc(g: ^Grid, kind: u32, rules: []Rule, random: ^MJRandom, steps: int) -> (int, bool) {
	if kind == 1 do return mj_run_one_rules_with_count(g, rules, random, steps)
	if kind == 2 do return mj_run_all_rules_with_count(g, rules, random, steps)
	return mj_run_parallel_rules_with_count(g, rules, random, steps)
}

mj_compute_node_fields :: proc(g: ^Grid, node: ^MJ_Node, rules: []Rule, random: ^MJRandom, counter: int) -> bool {
	if node.observations != nil && !node.future_computed {
		if !observations_compute_future_set_present(node.future, g.state, node.observations) do return false
		node.future_computed = true
		if node.search {
			if node.trajectory != nil { search_destroy_trajectory(node.trajectory); node.trajectory = nil }
			tries := 1
			if node.limit >= 0 do tries = 20
			for k := 0; k < tries && node.trajectory == nil; k += 1 {
				node.trajectory = search_run(g.state, node.future, rules, g.mx, g.my, g.mz, len(g.characters), node.kind == 2, node.limit, node.depth_coefficient, mj_random_next(random))
			}
		} else {
			observations_compute_backward_potentials(node.potentials, node.future, g.mx, g.my, g.mz, len(g.characters), rules)
		}
	}
	if node.potentials == nil || node.observations != nil do return true
	any_success := false
	any_computation := false
	state_len := len(g.state)
	for c in 0..<len(node.fields) {
		f := &node.fields[c]
		if f.present && (counter == 0 || f.recompute) {
			success := field_compute(f, node.potentials[c * state_len:(c + 1) * state_len], g)
			if !success && f.essential do return false
			any_success = any_success || success
			any_computation = true
		}
	}
	if any_computation && !any_success do return false
	return true
}

mj_run_all_node_with_fields_count :: proc(g: ^Grid, node: ^MJ_Node, rules: []Rule, random: ^MJRandom, steps: int) -> (int, bool) {
	matches := make([dynamic]Match)
	defer delete(matches)
	match_mask := make([][]bool, len(rules))
	defer {
		for i in 0..<len(match_mask) { if match_mask[i] != nil do delete(match_mask[i]) }
		delete(match_mask)
	}
	for r in 0..<len(rules) do match_mask[r] = make([]bool, len(g.state))

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
		if !mj_compute_node_fields(g, node, rules, random, counter) do break
		clear(&matches)
		if first_turn {
			one_initial_scan(g, rules, &matches, match_mask)
			first_turn = false
		} else {
			one_add_around_changes(g, rules, previous_changes[:], &matches, match_mask)
		}
		if len(matches) == 0 do break

		clear(&current_changes)
		mj_apply_all_matches_with_fields(g, node, rules, matches[:], match_mask, mask, random, &current_changes)
		for c in current_changes do mask[c.x + c.y * g.mx + c.z * g.mx * g.my] = false
		clear(&previous_changes)
		for c in current_changes do append(&previous_changes, c)
		counter += 1
		changed = true
	}
	return counter, changed
}

mj_run_one_node_with_fields_count :: proc(g: ^Grid, node: ^MJ_Node, rules: []Rule, random: ^MJRandom, steps: int) -> (int, bool) {
	matches := make([dynamic]Match)
	defer delete(matches)
	match_mask := make([][]bool, len(rules))
	defer {
		for i in 0..<len(match_mask) { if match_mask[i] != nil do delete(match_mask[i]) }
		delete(match_mask)
	}
	for r in 0..<len(rules) do match_mask[r] = make([]bool, len(g.state))

	one_initial_scan(g, rules, &matches, match_mask)
	changes := make([dynamic]Cell)
	defer delete(changes)

	counter := 0
	changed := false
	for (steps <= 0 || counter < steps) && len(matches) > 0 {
		if !mj_compute_node_fields(g, node, rules, random, counter) do break
		if node.observations != nil && observations_goal_reached(g.state, node.future) {
			node.future_computed = false
			break
		}
		argmax := -1
		max_key := -1000.0
		first_h := 0
		first_set := false
		for k := 0; k < len(matches); k += 1 {
			m := matches[k]
			si := m.x + m.y * g.mx + m.z * g.mx * g.my
			if !grid_matches(g, &rules[m.r], m.x, m.y, m.z) {
				match_mask[m.r][si] = false
				matches[k] = matches[len(matches) - 1]
				_ = pop(&matches)
				k -= 1
			} else {
				h, ok := field_delta_pointwise(g.state, &rules[m.r], m.x, m.y, m.z, node.fields, node.potentials, len(g.characters), g.mx, g.my)
				if !ok do continue
				if !first_set { first_h = h; first_set = true }
				key := field_key(h, first_h, node.temperature, random)
				if key > max_key { max_key = key; argmax = k }
			}
		}
		if argmax < 0 do break
		m := matches[argmax]
		clear(&changes)
		one_apply(g, &rules[m.r], m.x, m.y, m.z, &changes)
		one_add_around_changes(g, rules, changes[:], &matches, match_mask)
		counter += 1
		changed = true
	}
	return counter, changed
}

mj_prepare_node_states :: proc(g: ^Grid, nodes: []MJ_Node) -> []MJ_Markov_State {
	state_len := len(g.state)
	for n in nodes {
		if n.has_map && len(n.map_state.grid.state) > state_len do state_len = len(n.map_state.grid.state)
		if n.has_wfc && len(n.wfc.newgrid.state) > state_len do state_len = len(n.wfc.newgrid.state)
	}
	states := make([]MJ_Markov_State, len(nodes))
	for i in 0..<len(nodes) {
		states[i].last_turn = -1
		if nodes[i].kind == 1 || nodes[i].kind == 2 {
			states[i].match_mask = make([][]bool, nodes[i].count)
			for r in 0..<nodes[i].count { states[i].match_mask[r] = make([]bool, state_len) }
		}
	}
	return states
}

mj_destroy_node_states :: proc(states: []MJ_Markov_State) {
	for i in 0..<len(states) {
		if states[i].matches != nil do delete(states[i].matches)
		if states[i].match_mask != nil {
			for r in 0..<len(states[i].match_mask) { if states[i].match_mask[r] != nil do delete(states[i].match_mask[r]) }
			delete(states[i].match_mask)
		}
	}
	delete(states)
}

mj_apply_all_matches_with_fields :: proc(g: ^Grid, node: ^MJ_Node, rules: []Rule, matches: []Match, match_mask: [][]bool, mask: []bool, random: ^MJRandom, changes: ^[dynamic]Cell) {
	Pair :: struct {idx: int, key: f64}
	list := make([dynamic]Pair)
	defer delete(list)
	first_h := 0
	first_set := false
	for m_idx in 0..<len(matches) {
		m := matches[m_idx]
		h, ok := field_delta_pointwise(g.state, &rules[m.r], m.x, m.y, m.z, node.fields, node.potentials, len(g.characters), g.mx, g.my)
		if ok {
			if !first_set { first_h = h; first_set = true }
			append(&list, Pair{m_idx, field_key(h, first_h, node.temperature, random)})
		}
	}
	for i in 1..<len(list) {
		v := list[i]
		j := i - 1
		for ; j >= 0 && list[j].key < v.key; j -= 1 {
			list[j + 1] = list[j]
			if j == 0 { j = -1; break }
		}
		list[j + 1] = v
	}
	for p in list {
		m := matches[p.idx]
		si := m.x + m.y * g.mx + m.z * g.mx * g.my
		match_mask[m.r][si] = false
		all_fit(g, &rules[m.r], m.x, m.y, m.z, mask, changes)
	}
}

mj_replay_search_trajectory :: proc(g: ^Grid, node: ^MJ_Node, node_counter: int, changes: ^[dynamic]Cell) -> bool {
	if node.trajectory == nil do return false
	if node_counter >= len(node.trajectory) do return false
	state := node.trajectory[node_counter]
	for i in 0..<len(g.state) {
		if g.state[i] != state[i] {
			g.state[i] = state[i]
			append(changes, Cell{i % g.mx, (i % (g.mx * g.my)) / g.mx, i / (g.mx * g.my)})
		}
	}
	return true
}

mj_markov_one_go_with_fields :: proc(g: ^Grid, node: ^MJ_Node, rules: []Rule, random: ^MJRandom, state: ^MJ_Markov_State, changes_snapshot: []Cell, first: []int, turn: int, changes: ^[dynamic]Cell, node_counter: int) -> bool {
	if len(rules) == 0 { return false }
	if !mj_compute_node_fields(g, node, rules, random, node_counter) do return false
	if mj_replay_search_trajectory(g, node, node_counter, changes) do return true
	if state.last_turn >= 0 {
		start := first[state.last_turn]
		for ci := start; ci < len(changes_snapshot); ci += 1 {
			c := changes_snapshot[ci]
			value := g.state[c.x + c.y * g.mx + c.z * g.mx * g.my]
			for r in 0..<len(rules) {
				rule := &rules[r]
				for shift in rule.ishifts[value] do mj_markov_one_try_add(g, rules, r, c.x - shift.x, c.y - shift.y, c.z - shift.z, state)
			}
		}
	} else {
		clear(&state.matches)
		for r in 0..<len(state.match_mask) { for i in 0..<len(state.match_mask[r]) { state.match_mask[r][i] = false } }
		for r in 0..<len(rules) {
			rule := &rules[r]
			for z := rule.imz - 1; z < g.mz; z += rule.imz {
				for y := rule.imy - 1; y < g.my; y += rule.imy {
					for x := rule.imx - 1; x < g.mx; x += rule.imx {
						value := g.state[x + y * g.mx + z * g.mx * g.my]
						for shift in rule.ishifts[value] do mj_markov_one_try_add(g, rules, r, x - shift.x, y - shift.y, z - shift.z, state)
					}
				}
			}
		}
	}
	state.last_turn = turn
	if node.observations != nil && observations_goal_reached(g.state, node.future) {
		node.future_computed = false
		return false
	}
	argmax := -1
	max_key := -1000.0
	first_h := 0
	first_set := false
	for k := 0; k < len(state.matches); k += 1 {
		m := state.matches[k]
		si := m.x + m.y * g.mx + m.z * g.mx * g.my
		if !grid_matches(g, &rules[m.r], m.x, m.y, m.z) {
			state.match_mask[m.r][si] = false
			state.matches[k] = state.matches[len(state.matches) - 1]
			_ = pop(&state.matches)
			k -= 1
		} else {
			h, ok := field_delta_pointwise(g.state, &rules[m.r], m.x, m.y, m.z, node.fields, node.potentials, len(g.characters), g.mx, g.my)
			if !ok do continue
			if !first_set { first_h = h; first_set = true }
			key := field_key(h, first_h, node.temperature, random)
			if key > max_key { max_key = key; argmax = k }
		}
	}
	if argmax < 0 do return false
	m := state.matches[argmax]
	one_apply(g, &rules[m.r], m.x, m.y, m.z, changes)
	return true
}

mj_markov_all_go :: proc(g: ^Grid, node: ^MJ_Node, rules: []Rule, random: ^MJRandom, state: ^MJ_Markov_State, changes_snapshot: []Cell, first: []int, turn: int, changes: ^[dynamic]Cell, node_counter: int) -> bool {
	if len(rules) == 0 { return false }
	if state.last_turn >= 0 {
		start := first[state.last_turn]
		one_add_around_changes(g, rules, changes_snapshot[start:], &state.matches, state.match_mask)
	} else {
		one_initial_scan(g, rules, &state.matches, state.match_mask)
	}
	if !mj_compute_node_fields(g, node, rules, random, node_counter) do return false
	state.last_turn = turn
	if len(state.matches) == 0 do return false
	mask := make([]bool, len(g.state))
	defer delete(mask)
	turn_changes := make([dynamic]Cell)
	defer delete(turn_changes)
	if node.potentials != nil {
		mj_apply_all_matches_with_fields(g, node, rules, state.matches[:], state.match_mask, mask, random, &turn_changes)
	} else {
		shuffle := make([]int, len(state.matches))
		defer delete(shuffle)
		for i in 0..<len(shuffle) {
			j := int(mj_random_next_max(random, i32(i + 1)))
			shuffle[i] = shuffle[j]
			shuffle[j] = i
		}
		for k in 0..<len(shuffle) {
			m := state.matches[shuffle[k]]
			si := m.x + m.y * g.mx + m.z * g.mx * g.my
			state.match_mask[m.r][si] = false
			all_fit(g, &rules[m.r], m.x, m.y, m.z, mask, &turn_changes)
		}
	}
	for c in turn_changes {
		mask[c.x + c.y * g.mx + c.z * g.mx * g.my] = false
		append(changes, c)
	}
	clear(&state.matches)
	return len(turn_changes) > 0
}

mj_run_node_once_with_fields :: proc(g: ^Grid, node: ^MJ_Node, rules: []Rule, random: ^MJRandom, changes: ^[dynamic]Cell, node_counter: int) -> bool {
	if node.kind == 6 do return path_go(&node.path, g, random, changes)
	if node.kind == 7 do return convolution_go(&node.convolution, g, random)
	if node.kind == 8 do return convchain_go(&node.convchain, g, random)
	if node.kind == 9 do return wfc_go(&node.wfc, g, random)
	if node.kind == 10 {
		if node.map_state.mapped do return false
		map_go_initial(&node.map_state, g)
		return true
	}
	if node.kind == 2 && (node.potentials != nil || node.search) {
		if !mj_compute_node_fields(g, node, rules, random, node_counter) do return false
		if mj_replay_search_trajectory(g, node, node_counter, changes) do return true
		if node.potentials == nil do return mj_run_node_once_with_changes(g, node.kind, rules, random, changes)
		matches := make([dynamic]Match)
		defer delete(matches)
		match_mask := make([][]bool, len(rules))
		defer {
			for i in 0..<len(match_mask) { if match_mask[i] != nil do delete(match_mask[i]) }
			delete(match_mask)
		}
		for r in 0..<len(rules) do match_mask[r] = make([]bool, len(g.state))
		one_initial_scan(g, rules, &matches, match_mask)
		if len(matches) == 0 do return false
		mask := make([]bool, len(g.state))
		defer delete(mask)
		turn_changes := make([dynamic]Cell)
		defer delete(turn_changes)
		mj_apply_all_matches_with_fields(g, node, rules, matches[:], match_mask, mask, random, &turn_changes)
		for c in turn_changes {
			mask[c.x + c.y * g.mx + c.z * g.mx * g.my] = false
			append(changes, c)
		}
		return len(turn_changes) > 0
	}
	return mj_run_node_once_with_changes(g, node.kind, rules, random, changes)
}

mj_markov_range_go :: proc(g: ^Grid, rules: []Rule, nodes: []MJ_Node, start, count: int, random: ^MJRandom, states: []MJ_Markov_State, counters, positions, active: []int, changes: ^[dynamic]Cell, first: ^[dynamic]int, counter: int, parent_idx: int) -> bool {
	parent_slot := parent_idx + 1
	start_child := 0
	if active[parent_slot] > 0 do start_child = active[parent_slot] - 1
	for child := start_child; child < count; child += 1 {
		idx := start + child
		node := nodes[idx]
		if node.kind >= 4 && node.children_count > 0 {
			if node.steps > 0 && counters[idx] >= node.steps { child += node.children_count; continue }
			was_active := counters[idx] > 0
			node_changed := false
			if node.kind == 9 && nodes[idx].wfc.counter < 0 {
				node_changed = wfc_go(&nodes[idx].wfc, g, random)
			} else if node.kind == 10 && !nodes[idx].map_state.mapped {
				map_go_initial(&nodes[idx].map_state, g)
				node_changed = true
			} else if node.kind == 4 {
				node_changed = mj_markov_range_go(g, rules, nodes, node.children_start, node.children_count, random, states, counters, positions, active, changes, first, counter, idx)
			} else {
				node_changed = mj_sequence_range_go(g, rules, nodes, node.children_start, node.children_count, random, states, counters, positions, active, changes, first, counter, &positions[idx])
			}
			if node_changed {
				counters[idx] += 1
				active[parent_slot] = child + 1
				return true
			}
			if was_active {
				if node.kind == 9 && positions[idx] < 0 {
					positions[idx] = -positions[idx] - 1
					active[parent_slot] = child + 1
					return false
				}
				if node.kind == 10 {
					if positions[idx] < 0 {
						positions[idx] = -positions[idx] - 1
						active[parent_slot] = child + 1
						return false
					}
					active[parent_slot] = child + 1
					return false
				}
				active[parent_slot] = 0
				mj_reset_runtime_range(nodes, states, counters, positions, active, idx, node.children_count + 1)
				return false
			}
			child += node.children_count
			continue
		}
		if node.kind != 6 && node.kind != 7 && node.kind != 8 && node.kind != 9 && node.kind != 10 && node.count <= 0 { continue }
		if node.steps > 0 && counters[idx] >= node.steps { continue }
		if node.kind == 1 {
			changed := false
			if node.potentials != nil || node.search {
				changed = mj_markov_one_go_with_fields(g, &nodes[idx], rules[node.start:node.start + node.count], random, &states[idx], changes[:], first[:], counter, changes, counters[idx])
			} else {
				changed = mj_markov_one_go(g, rules[node.start:node.start + node.count], random, &states[idx], changes[:], first[:], counter, changes)
			}
			if changed {
				counters[idx] += 1
				return true
			}
		} else {
			node_changed := false
			if node.kind == 2 {
				node_changed = mj_markov_all_go(g, &nodes[idx], rules[node.start:node.start + node.count], random, &states[idx], changes[:], first[:], counter, changes, counters[idx])
			} else {
				node_changed = mj_run_node_once_with_fields(g, &nodes[idx], rules[node.start:node.start + node.count], random, changes, counters[idx])
			}
			if node_changed {
				counters[idx] += 1
				return true
			}
		}
	}
	return false
}

mj_markov_nodes_go :: proc(g: ^Grid, rules: []Rule, nodes: []MJ_Node, random: ^MJRandom, states: []MJ_Markov_State, counters: []int, changes: ^[dynamic]Cell, first: ^[dynamic]int, counter: int) -> bool {
	positions := make([]int, len(nodes))
	defer delete(positions)
	active := make([]int, len(nodes) + 1)
	defer delete(active)
	return mj_markov_range_go(g, rules, nodes, 0, len(nodes), random, states, counters, positions, active, changes, first, counter, -1)
}

mj_run_markov_nodes_with_count :: proc(g: ^Grid, rules: []Rule, nodes: []MJ_Node, random: ^MJRandom, steps: int) -> (int, bool) {
	counter := 0
	changed_any := false
	states := mj_prepare_node_states(g, nodes)
	defer mj_destroy_node_states(states)
	counters := make([]int, len(nodes))
	defer delete(counters)
	positions := make([]int, len(nodes))
	defer delete(positions)
	active := make([]int, len(nodes) + 1)
	defer delete(active)

	changes := make([dynamic]Cell)
	defer delete(changes)
	first := make([dynamic]int)
	defer delete(first)
	append(&first, 0)

	for steps <= 0 || counter < steps {
		changed := mj_markov_range_go(g, rules, nodes, 0, len(nodes), random, states, counters, positions, active, &changes, &first, counter, -1)
		if !changed { break }
		changed_any = true
		counter += 1
		append(&first, len(changes))
	}
	return counter, changed_any
}

mj_reset_runtime_range :: proc(nodes: []MJ_Node, states: []MJ_Markov_State, counters, positions, active: []int, start, count: int) {
	for i in start..<start + count {
		counters[i] = 0
		positions[i] = 0
		active[i + 1] = 0
		states[i].last_turn = -1
		nodes[i].future_computed = false
		if nodes[i].trajectory != nil { search_destroy_trajectory(nodes[i].trajectory); nodes[i].trajectory = nil }
		nodes[i].convolution.counter = 0
		nodes[i].convchain.counter = 0
		if nodes[i].has_wfc {
			nodes[i].wfc.counter = -1
			nodes[i].wfc.firstgo = true
			nodes[i].wfc.stacksize = 0
		}
		if nodes[i].has_map do nodes[i].map_state.mapped = false
		if states[i].matches != nil do clear(&states[i].matches)
		if states[i].match_mask != nil {
			for r in 0..<len(states[i].match_mask) { for c in 0..<len(states[i].match_mask[r]) { states[i].match_mask[r][c] = false } }
		}
	}
}

mj_sequence_range_go :: proc(g: ^Grid, rules: []Rule, nodes: []MJ_Node, start, count: int, random: ^MJRandom, states: []MJ_Markov_State, counters, positions, active: []int, changes: ^[dynamic]Cell, first: ^[dynamic]int, counter: int, child: ^int) -> bool {
	for child^ < count {
		idx := start + child^
		node := nodes[idx]
		if node.kind >= 4 && node.children_count > 0 {
			if node.steps > 0 && counters[idx] >= node.steps {
				child^ += node.children_count + 1
				continue
			}
			was_active := counters[idx] > 0
			node_changed := false
			if node.kind == 9 && nodes[idx].wfc.counter < 0 {
				node_changed = wfc_go(&nodes[idx].wfc, g, random)
			} else if node.kind == 10 && !nodes[idx].map_state.mapped {
				map_go_initial(&nodes[idx].map_state, g)
				node_changed = true
			} else if node.kind == 4 {
				node_changed = mj_markov_range_go(g, rules, nodes, node.children_start, node.children_count, random, states, counters, positions, active, changes, first, counter, idx)
			} else {
				node_changed = mj_sequence_range_go(g, rules, nodes, node.children_start, node.children_count, random, states, counters, positions, active, changes, first, counter, &positions[idx])
			}
			if node_changed {
				counters[idx] += 1
				return true
			}
			if was_active {
				if node.kind == 9 {
					if positions[idx] < 0 {
						positions[idx] = -positions[idx] - 1
						child^ = -child^ - 1
						return false
					}
					child^ += node.children_count + 1
					return false
				}
				if node.kind == 10 {
					if positions[idx] < 0 {
						positions[idx] = -positions[idx] - 1
						child^ = -child^ - 1
						return false
					}
					child^ += node.children_count + 1
					return false
				}
				mj_reset_runtime_range(nodes, states, counters, positions, active, idx, node.children_count + 1)
				child^ = -child^ - 1
				return false
			}
			child^ += node.children_count + 1
			continue
		}
		if (node.kind != 6 && node.kind != 7 && node.kind != 8 && node.kind != 9 && node.kind != 10 && node.count <= 0) || (node.steps > 0 && counters[idx] >= node.steps) {
			child^ += 1
			continue
		}
		if node.kind == 1 {
			changed := false
			if node.potentials != nil || node.search {
				changed = mj_markov_one_go_with_fields(g, &nodes[idx], rules[node.start:node.start + node.count], random, &states[idx], changes[:], first[:], counter, changes, counters[idx])
			} else {
				changed = mj_markov_one_go(g, rules[node.start:node.start + node.count], random, &states[idx], changes[:], first[:], counter, changes)
			}
			if changed {
				counters[idx] += 1
				return true
			}
		} else {
			node_changed := false
			if node.kind == 2 {
				node_changed = mj_markov_all_go(g, &nodes[idx], rules[node.start:node.start + node.count], random, &states[idx], changes[:], first[:], counter, changes, counters[idx])
			} else {
				node_changed = mj_run_node_once_with_fields(g, &nodes[idx], rules[node.start:node.start + node.count], random, changes, counters[idx])
			}
			if node_changed {
				counters[idx] += 1
				return true
			}
		}
		child^ += 1
	}
	mj_reset_runtime_range(nodes, states, counters, positions, active, start, count)
	child^ = 0
	return false
}

mj_run_sequence_nodes_with_count :: proc(g: ^Grid, rules: []Rule, nodes: []MJ_Node, random: ^MJRandom, steps: int) -> (int, bool) {
	states := mj_prepare_node_states(g, nodes)
	defer mj_destroy_node_states(states)
	counters := make([]int, len(nodes))
	defer delete(counters)
	positions := make([]int, len(nodes))
	defer delete(positions)
	active := make([]int, len(nodes) + 1)
	defer delete(active)
	changes := make([dynamic]Cell)
	defer delete(changes)
	first := make([dynamic]int)
	defer delete(first)
	append(&first, 0)

	child := 0
	counter := 0
	changed_any := false
	for child < len(nodes) && (steps <= 0 || counter < steps) {
		changed := mj_sequence_range_go(g, rules, nodes, 0, len(nodes), random, states, counters, positions, active, &changes, &first, counter, &child)
		if changed do changed_any = true
		counter += 1
		append(&first, len(changes))
		if !changed {
			if child < 0 {
				child = -child - 1
				continue
			}
			// Original persistent execution keeps a current node pointer. If a root
			// sequence consists of a single nested markov/sequence container, completing
			// that child returns control to the root, which can enter the same child
			// again on the next outer turn (for example MultiHeadedWalk). Multi-child
			// root sequences complete to nil and stop (for example Division/Dwarves).
			// Do not apply this restart exception to leaf executable nodes such as WFC:
			// tile WFC swaps `g` to its expanded output grid on completion, while its
			// wave remains allocated for the coarse grid.
			if !(steps > 0 && len(nodes) == 1 + nodes[0].children_count && (nodes[0].kind == 4 || nodes[0].kind == 5)) { break }
		}
	}
	return counter, changed_any
}

mj_run_node_once_with_changes :: proc(g: ^Grid, kind: u32, rules: []Rule, random: ^MJRandom, changes: ^[dynamic]Cell) -> bool {
	if kind == 2 do return mj_run_all_once_with_changes(g, rules, random, changes)
	return mj_run_parallel_once_with_changes(g, rules, random, changes)
}

mj_run_all_once_with_changes :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, changes: ^[dynamic]Cell) -> bool {
	matches := make([dynamic]Match)
	defer delete(matches)
	match_mask := make([][]bool, len(rules))
	defer {
		for i in 0..<len(match_mask) { if match_mask[i] != nil do delete(match_mask[i]) }
		delete(match_mask)
	}
	for r in 0..<len(rules) { match_mask[r] = make([]bool, len(g.state)) }
	one_initial_scan(g, rules, &matches, match_mask)
	if len(matches) == 0 { return false }

	mask := make([]bool, len(g.state))
	defer delete(mask)
	turn_changes := make([dynamic]Cell)
	defer delete(turn_changes)
	shuffle := make([]int, len(matches))
	defer delete(shuffle)
	for i in 0..<len(shuffle) {
		j := int(mj_random_next_max(random, i32(i + 1)))
		shuffle[i] = shuffle[j]
		shuffle[j] = i
	}
	for k in 0..<len(shuffle) {
		m := matches[shuffle[k]]
		all_fit(g, &rules[m.r], m.x, m.y, m.z, mask, &turn_changes)
	}
	for c in turn_changes {
		mask[c.x + c.y * g.mx + c.z * g.mx * g.my] = false
		append(changes, c)
	}
	return len(turn_changes) > 0
}

mj_run_parallel_once_with_changes :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, changes: ^[dynamic]Cell) -> bool {
	turn_changes := make([dynamic]Cell)
	defer delete(turn_changes)
	newstate := make([]u8, len(g.state))
	defer delete(newstate)
	parallel_initial_scan(g, rules, random, newstate, &turn_changes)
	if len(turn_changes) == 0 { return false }
	for c in turn_changes {
		i := c.x + c.y * g.mx + c.z * g.mx * g.my
		g.state[i] = newstate[i]
		append(changes, c)
	}
	return true
}

mj_markov_one_go :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, state: ^MJ_Markov_State, changes_snapshot: []Cell, first: []int, turn: int, changes: ^[dynamic]Cell) -> bool {
	if len(rules) == 0 { return false }
	if state.last_turn >= 0 {
		start := first[state.last_turn]
		for ci := start; ci < len(changes_snapshot); ci += 1 {
			c := changes_snapshot[ci]
			value := g.state[c.x + c.y * g.mx + c.z * g.mx * g.my]
			for r in 0..<len(rules) {
				rule := &rules[r]
				for shift in rule.ishifts[value] {
					mj_markov_one_try_add(g, rules, r, c.x - shift.x, c.y - shift.y, c.z - shift.z, state)
				}
			}
		}
	} else {
		clear(&state.matches)
		for r in 0..<len(state.match_mask) { for i in 0..<len(state.match_mask[r]) { state.match_mask[r][i] = false } }
		for r in 0..<len(rules) {
			rule := &rules[r]
			for z := rule.imz - 1; z < g.mz; z += rule.imz {
				for y := rule.imy - 1; y < g.my; y += rule.imy {
					for x := rule.imx - 1; x < g.mx; x += rule.imx {
						value := g.state[x + y * g.mx + z * g.mx * g.my]
						for shift in rule.ishifts[value] {
							mj_markov_one_try_add(g, rules, r, x - shift.x, y - shift.y, z - shift.z, state)
						}
					}
				}
			}
		}
	}
	state.last_turn = turn

	for len(state.matches) > 0 {
		arg := int(mj_random_next_max(random, i32(len(state.matches))))
		m := state.matches[arg]
		si := m.x + m.y * g.mx + m.z * g.mx * g.my
		state.match_mask[m.r][si] = false
		state.matches[arg] = state.matches[len(state.matches) - 1]
		_ = pop(&state.matches)

		if grid_matches(g, &rules[m.r], m.x, m.y, m.z) {
			one_apply(g, &rules[m.r], m.x, m.y, m.z, changes)
			return true
		}
	}
	return false
}

mj_markov_one_try_add :: proc(g: ^Grid, rules: []Rule, r, sx, sy, sz: int, state: ^MJ_Markov_State) {
	rule := &rules[r]
	if sx < 0 || sy < 0 || sz < 0 || sx + rule.imx > g.mx || sy + rule.imy > g.my || sz + rule.imz > g.mz { return }
	si := sx + sy * g.mx + sz * g.mx * g.my
	if !state.match_mask[r][si] && grid_matches(g, rule, sx, sy, sz) {
		state.match_mask[r][si] = true
		append(&state.matches, Match{r, sx, sy, sz})
	}
}

mj_run_one_rules_with_count :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, steps: int) -> (int, bool) {
	matches := make([dynamic]Match)
	defer delete(matches)
	match_mask := make([][]bool, len(rules))
	defer {
		for i in 0..<len(match_mask) { if match_mask[i] != nil do delete(match_mask[i]) }
		delete(match_mask)
	}
	for r in 0..<len(rules) { match_mask[r] = make([]bool, len(g.state)) }
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
	return counter, changed
}

mj_run_all_rules_with_count :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, steps: int) -> (int, bool) {
	matches := make([dynamic]Match)
	defer delete(matches)
	match_mask := make([][]bool, len(rules))
	defer {
		for i in 0..<len(match_mask) { if match_mask[i] != nil do delete(match_mask[i]) }
		delete(match_mask)
	}
	for r in 0..<len(rules) { match_mask[r] = make([]bool, len(g.state)) }

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

		if len(matches) == 0 { break }

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

		for c in current_changes { mask[c.x + c.y * g.mx + c.z * g.mx * g.my] = false }

		clear(&previous_changes)
		for c in current_changes { append(&previous_changes, c) }

		counter += 1
		changed = true
	}
	return counter, changed
}

mj_run_parallel_rules_with_count :: proc(g: ^Grid, rules: []Rule, random: ^MJRandom, steps: int) -> (int, bool) {
	current_changes := make([dynamic]Cell)
	defer delete(current_changes)
	newstate := make([]u8, len(g.state))
	defer delete(newstate)

	counter := 0
	changed := false
	for steps <= 0 || counter < steps {
		clear(&current_changes)
		parallel_initial_scan(g, rules, random, newstate, &current_changes)

		if len(current_changes) == 0 { break }

		for c in current_changes {
			i := c.x + c.y * g.mx + c.z * g.mx * g.my
			g.state[i] = newstate[i]
		}

		counter += 1
		changed = true
	}
	return counter, changed
}

mj_any_one_match :: proc(g: ^Grid, rules: []Rule) -> bool {
	for r in 0..<len(rules) {
		rule := &rules[r]
		for z := rule.imz - 1; z < g.mz; z += rule.imz {
			for y := rule.imy - 1; y < g.my; y += rule.imy {
				for x := rule.imx - 1; x < g.mx; x += rule.imx {
					value := g.state[x + y * g.mx + z * g.mx * g.my]
					if int(value) >= len(rule.ishifts) do continue
					for shift in rule.ishifts[value] {
						sx := x - shift.x; sy := y - shift.y; sz := z - shift.z
						if sx < 0 || sy < 0 || sz < 0 || sx + rule.imx > g.mx || sy + rule.imy > g.my || sz + rule.imz > g.mz { continue }
						if grid_matches(g, rule, sx, sy, sz) { return true }
					}
				}
			}
		}
	}
	return false
}

mj_respond_grid :: proc(g: ^Grid, steps_run: u32, changed, done: bool) -> u32 {
	values_len := len(g.characters)
	cell_count := len(g.state)
	out_pos := 0
	if out_pos + 32 + values_len + cell_count > len(mj_output_buffer) { return mj_fail("result too large") }
	mj_output_buffer[0] = 'M'; mj_output_buffer[1] = 'J'; mj_output_buffer[2] = 'R'; mj_output_buffer[3] = 'O'
	out_pos = 4
	_ = mj_write_u32(&out_pos, u32(g.mx)); _ = mj_write_u32(&out_pos, u32(g.my)); _ = mj_write_u32(&out_pos, u32(g.mz))
	_ = mj_write_u32(&out_pos, steps_run)
	_ = mj_write_u32(&out_pos, 0); if changed { mj_output_buffer[out_pos - 4] = 1 }
	_ = mj_write_u32(&out_pos, 0); if done { mj_output_buffer[out_pos - 4] = 1 }
	_ = mj_write_u32(&out_pos, u32(values_len))
	copy(mj_output_buffer[out_pos:out_pos + values_len], transmute([]u8)g.characters); out_pos += values_len
	_ = mj_write_u32(&out_pos, u32(cell_count))
	copy(mj_output_buffer[out_pos:out_pos + cell_count], g.state)
	mj_output_len = out_pos + cell_count
	return 0
}
