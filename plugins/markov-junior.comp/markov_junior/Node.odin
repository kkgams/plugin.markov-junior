package markov_junior

// Port of source/Node.cs.
// Includes Branch/Sequence/Markov execution state while the port is being expanded.

import xml "core:encoding/xml"
import "core:fmt"
import "core:os"

Exec_Context :: struct {
	changes: [dynamic]Cell,
	first:   [dynamic]int,
	counter: int,
}

Persistent_Kind :: enum {
	One,
	All,
	Prl,
	Path,
	Convolution,
	ConvChain,
	WFC,
	Map,
	Markov,
	Sequence,
}

Persistent_Node :: struct {
	kind: Persistent_Kind,
	rules: [dynamic]Rule,
	children: [dynamic]^Persistent_Node,
	parent: ^Persistent_Node,
	n: int,
	debug_index: int,
	matches: [dynamic]Match,
	match_count: int,
	match_mask: [][]bool,
	all_mask: []bool,
	newstate: []u8,
	path: Path_State,
	convolution: Convolution_State,
	convchain: ConvChain_State,
	wfc: WFC_State,
	map_state: Map_State,
	fields: []Field_State,
	observations: []Observation_State,
	potentials: []int,
	future: []i32,
	trajectory: [][]u8,
	search: bool,
	limit: int,
	depth_coefficient: f64,
	future_computed: bool,
	temperature: f64,
	last_matched_turn: int,
	counter: int,
	steps: int,
}

persistent_node_destroy :: proc(n: ^Persistent_Node) {
	for i in 0..<len(n.children) {
		persistent_node_destroy(n.children[i])
		free(n.children[i])
	}
	if n.children != nil do delete(n.children)
	for i in 0..<len(n.rules) do rule_destroy(&n.rules[i])
	if n.rules != nil do delete(n.rules)
	if n.matches != nil do delete(n.matches)
	if n.match_mask != nil {
		for i in 0..<len(n.match_mask) {
			if n.match_mask[i] != nil do delete(n.match_mask[i])
		}
		delete(n.match_mask)
	}
	if n.all_mask != nil do delete(n.all_mask)
	if n.newstate != nil do delete(n.newstate)
	convolution_destroy(&n.convolution)
	convchain_destroy(&n.convchain)
	wfc_destroy(&n.wfc)
	map_destroy(&n.map_state)
	if n.fields != nil do delete(n.fields)
	if n.observations != nil do delete(n.observations)
	if n.potentials != nil do delete(n.potentials)
	if n.future != nil do delete(n.future)
	if n.trajectory != nil do search_destroy_trajectory(n.trajectory)
}

persistent_node_reset :: proc(n: ^Persistent_Node) {
	n.n = 0
	if n.kind == .Map || n.kind == .WFC do n.n = -1
	n.counter = 0
	n.last_matched_turn = -1
	n.match_count = 0
	n.future_computed = false
	if n.trajectory != nil { search_destroy_trajectory(n.trajectory); n.trajectory = nil }
	if n.match_mask != nil {
		for r in 0..<len(n.match_mask) {
			for i in 0..<len(n.match_mask[r]) do n.match_mask[r][i] = false
		}
	}
	if n.all_mask != nil {
		for i in 0..<len(n.all_mask) do n.all_mask[i] = false
	}
	for child in n.children do persistent_node_reset(child)
}

persistent_load_node :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid, debug_counter: ^int, parent_symmetry := "") -> ^Persistent_Node {
	kind_string := doc.elements[id].ident
	n := new(Persistent_Node)
	n.debug_index = debug_counter^
	debug_counter^ += 1
	n.last_matched_turn = -1
	n.steps = xml_attr_int(doc, id, "steps", 0)
	node_symmetry := xml_attr(doc, id, "symmetry", parent_symmetry)
	if kind_string == "markov" {
		n.kind = .Markov
		persistent_load_children(doc, id, g, n, debug_counter, node_symmetry)
	} else if kind_string == "sequence" {
		n.kind = .Sequence
		persistent_load_children(doc, id, g, n, debug_counter, node_symmetry)
	} else if kind_string == "path" {
		n.kind = .Path
		n.path = path_load(doc, id, g)
	} else if kind_string == "convolution" {
		n.kind = .Convolution
		n.convolution = convolution_load(doc, id, g)
	} else if kind_string == "convchain" {
		n.kind = .ConvChain
		n.convchain = convchain_load(doc, id, g, node_symmetry)
	} else if kind_string == "wfc" {
		n.kind = .WFC
		n.n = -1
		if len(xml_attr(doc, id, "sample", "")) > 0 {
			n.wfc = wfc_load_overlap(doc, id, g, parent_symmetry)
		} else if len(xml_attr(doc, id, "tileset", "")) > 0 {
			n.wfc = wfc_load_tile(doc, id, g, parent_symmetry)
		}
		persistent_load_children(doc, id, &n.wfc.newgrid, n, debug_counter, node_symmetry)
	} else if kind_string == "map" {
		n.kind = .Map
		n.n = -1
		n.map_state = map_load(doc, id, g, parent_symmetry)
		persistent_load_children(doc, id, &n.map_state.grid, n, debug_counter, node_symmetry)
	} else if kind_string == "one" || kind_string == "all" || kind_string == "prl" {
		if kind_string == "one" {
			n.kind = .One
		} else if kind_string == "all" {
			n.kind = .All
		} else {
			n.kind = .Prl
		}
		load_rules_for_element(doc, id, g, &n.rules, parent_symmetry)
		if n.kind != .Prl {
			n.match_mask = make([][]bool, len(n.rules))
			for r in 0..<len(n.rules) do n.match_mask[r] = make([]bool, len(g.state))
		}
		if n.kind == .All do n.all_mask = make([]bool, len(g.state))
		if n.kind == .Prl do n.newstate = make([]u8, len(g.state))
		persistent_load_fields_and_observations(doc, id, g, n)
	} else {
		free(n)
		return nil
	}
	return n
}

persistent_load_fields_and_observations :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid, n: ^Persistent_Node) {
	n.temperature = xml_attr_f64(doc, id, "temperature", 0.0)
	for value in doc.elements[id].value {
		#partial switch child_id in value {
		case xml.Element_ID:
			if doc.elements[child_id].ident == "field" {
				if n.fields == nil {
					n.fields = make([]Field_State, len(g.characters))
					n.potentials = make([]int, len(g.state) * len(g.characters))
				}
				ch := xml_attr(doc, child_id, "for")[0]
				n.fields[grid_value(g, ch)] = field_load(doc, child_id, g)
			} else if doc.elements[child_id].ident == "observe" {
				if n.observations == nil {
					n.observations = make([]Observation_State, len(g.characters))
					n.search = xml_attr_bool(doc, id, "search")
					n.limit = xml_attr_int(doc, id, "limit", -1)
					n.depth_coefficient = xml_attr_f64(doc, id, "depthCoefficient", 0.5)
					if !n.search do n.potentials = make([]int, len(g.state) * len(g.characters))
					n.future = make([]i32, len(g.state))
				}
				value, obs := observation_load(doc, child_id, g)
				n.observations[value] = obs
			}
		}
	}
}

persistent_load_children :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid, n: ^Persistent_Node, debug_counter: ^int, parent_symmetry: string) {
	for value in doc.elements[id].value {
		#partial switch child_id in value {
		case xml.Element_ID:
			child_kind := doc.elements[child_id].ident
			if child_kind == "one" || child_kind == "all" || child_kind == "prl" || child_kind == "path" || child_kind == "convolution" || child_kind == "convchain" || child_kind == "wfc" || child_kind == "map" || child_kind == "markov" || child_kind == "sequence" {
				child := persistent_load_node(doc, child_id, g, debug_counter, parent_symmetry)
				if child != nil {
					if child.kind == .Map || child.kind == .WFC {
						child.parent = nil
					} else {
						child.parent = n
					}
					append(&n.children, child)
				}
			}
		}
	}
}

run_persistent_markov_root :: proc(doc: ^xml.Document, root: xml.Element_ID, g: ^Grid, random: ^MJRandom, steps: int) -> bool {
	debug_counter := 0
	root_node := persistent_load_node(doc, root, g, &debug_counter)
	if root_node == nil do return false
	defer {
		persistent_node_destroy(root_node)
		free(root_node)
	}
	persistent_node_reset(root_node)
	ctx := Exec_Context{}
	defer {
		if ctx.changes != nil do delete(ctx.changes)
		if ctx.first != nil do delete(ctx.first)
	}
	append(&ctx.first, 0)
	changed_any := false
	current := root_node
	for current != nil && (steps <= 0 || ctx.counter < steps) {
		changed := persistent_node_go(current, &current, g, random, &ctx)
		ctx.counter += 1
		append(&ctx.first, len(ctx.changes))
		if changed do changed_any = true
	}
	persistent_apply_csharp_tile_wfc_output_timing(root_node, g)
	return changed_any
}

persistent_apply_csharp_tile_wfc_output_timing :: proc(n: ^Persistent_Node, g: ^Grid) -> bool {
	if n.kind == .WFC && n.wfc.tile_mode && !n.wfc.firstgo && n.wfc.counter < 0 {
		old := g^
		g^ = n.wfc.newgrid
		n.wfc.newgrid = old
		return true
	}
	for child in n.children do if persistent_apply_csharp_tile_wfc_output_timing(child, g) do return true
	return false
}

persistent_node_go :: proc(n: ^Persistent_Node, current: ^^Persistent_Node, g: ^Grid, random: ^MJRandom, ctx: ^Exec_Context) -> bool {
	switch n.kind {
	case .One:
		return persistent_one_go(n, g, random, ctx)
	case .All:
		return persistent_all_go(n, g, random, ctx)
	case .Prl:
		return persistent_prl_go(n, g, random, ctx)
	case .Path:
		return path_go(&n.path, g, random, &ctx.changes)
	case .Convolution:
		return convolution_go(&n.convolution, g, random)
	case .ConvChain:
		return convchain_go(&n.convchain, g, random)
	case .WFC:
		if n.n < 0 {
			if wfc_go(&n.wfc, g, random) {
				if n.wfc.counter >= 0 do n.n += 1
				return true
			}
			if n.wfc.counter >= 0 {
				n.n = 0
			} else {
				return false
			}
		}
		for ; n.n < len(n.children); n.n += 1 {
			child := n.children[n.n]
			if child.kind == .Markov || child.kind == .Sequence || child.kind == .Map || child.kind == .WFC do current^ = child
			if persistent_node_go(child, current, g, random, ctx) do return true
		}
		current^ = n.parent
		persistent_node_reset(n)
		return false
	case .Map:
		if n.n < 0 {
			map_go_initial(&n.map_state, g)
			n.n += 1
			return true
		}
		for ; n.n < len(n.children); n.n += 1 {
			child := n.children[n.n]
			if child.kind == .Markov || child.kind == .Sequence || child.kind == .Map || child.kind == .WFC do current^ = child
			if persistent_node_go(child, current, g, random, ctx) do return true
		}
		current^ = n.parent
		persistent_node_reset(n)
		return false
	case .Markov:
		n.n = 0
		for ; n.n < len(n.children); n.n += 1 {
			child := n.children[n.n]
			if child.kind == .Markov || child.kind == .Sequence || child.kind == .Map || child.kind == .WFC do current^ = child
			if persistent_node_go(child, current, g, random, ctx) do return true
		}
		current^ = n.parent
		persistent_node_reset(n)
		return false
	case .Sequence:
		for ; n.n < len(n.children); n.n += 1 {
			child := n.children[n.n]
			if child.kind == .Markov || child.kind == .Sequence || child.kind == .Map || child.kind == .WFC do current^ = child
			if persistent_node_go(child, current, g, random, ctx) do return true
		}
		current^ = n.parent
		persistent_node_reset(n)
		return false
	}
	return false
}



persistent_prl_go :: proc(n: ^Persistent_Node, g: ^Grid, random: ^MJRandom, ctx: ^Exec_Context) -> bool {
	if len(n.rules) == 0 do return false
	if n.steps > 0 && n.counter >= n.steps do return false
	n.match_count = 0

	for r in 0..<len(n.rules) {
		rule := &n.rules[r]
		for z := rule.imz - 1; z < g.mz; z += rule.imz {
			for y := rule.imy - 1; y < g.my; y += rule.imy {
				for x := rule.imx - 1; x < g.mx; x += rule.imx {
					value := g.state[x + y * g.mx + z * g.mx * g.my]
					for shift in rule.ishifts[value] {
						sx := x - shift.x
						sy := y - shift.y
						sz := z - shift.z
						persistent_prl_try_add(g, n, r, sx, sy, sz, random, ctx)
					}
				}
			}
		}
	}

	start := ctx.first[ctx.counter]
	for ci := start; ci < len(ctx.changes); ci += 1 {
		c := ctx.changes[ci]
		i := c.x + c.y * g.mx + c.z * g.mx * g.my
		g.state[i] = n.newstate[i]
	}

	n.counter += 1
	return n.match_count > 0
}

persistent_prl_try_add :: proc(g: ^Grid, n: ^Persistent_Node, r, sx, sy, sz: int, random: ^MJRandom, ctx: ^Exec_Context) {
	rule := &n.rules[r]
	if sx < 0 || sy < 0 || sz < 0 || sx + rule.imx > g.mx || sy + rule.imy > g.my || sz + rule.imz > g.mz do return
	if !grid_matches(g, rule, sx, sy, sz) do return
	if mj_random_next_f64(random) > rule.p do return

	for dz in 0..<rule.omz {
		for dy in 0..<rule.omy {
			for dx in 0..<rule.omx {
				new_value := rule.output[dx + dy * rule.omx + dz * rule.omx * rule.omy]
				idi := sx + dx + (sy + dy) * g.mx + (sz + dz) * g.mx * g.my
				if new_value != 0xff && new_value != g.state[idi] {
					n.newstate[idi] = new_value
					append(&ctx.changes, Cell{sx + dx, sy + dy, sz + dz})
				}
			}
		}
	}
	n.match_count += 1
}

persistent_rule_scan :: proc(n: ^Persistent_Node, g: ^Grid, ctx: ^Exec_Context) {
	if n.last_matched_turn >= 0 {
		start := ctx.first[n.last_matched_turn]
		for ci := start; ci < len(ctx.changes); ci += 1 {
			c := ctx.changes[ci]
			value := g.state[c.x + c.y * g.mx + c.z * g.mx * g.my]
			for r in 0..<len(n.rules) {
				rule := &n.rules[r]
				for shift in rule.ishifts[value] {
					persistent_one_try_add(g, n, r, c.x - shift.x, c.y - shift.y, c.z - shift.z)
				}
			}
		}
	} else {
		n.match_count = 0
		for r in 0..<len(n.match_mask) {
			for i in 0..<len(n.match_mask[r]) do n.match_mask[r][i] = false
		}
		for r in 0..<len(n.rules) {
			rule := &n.rules[r]
			for z := rule.imz - 1; z < g.mz; z += rule.imz {
				for y := rule.imy - 1; y < g.my; y += rule.imy {
					for x := rule.imx - 1; x < g.mx; x += rule.imx {
						value := g.state[x + y * g.mx + z * g.mx * g.my]
						for shift in rule.ishifts[value] {
							persistent_one_try_add(g, n, r, x - shift.x, y - shift.y, z - shift.z)
						}
					}
				}
			}
		}
	}
}

persistent_all_go :: proc(n: ^Persistent_Node, g: ^Grid, random: ^MJRandom, ctx: ^Exec_Context) -> bool {
	if len(n.rules) == 0 do return false
	if n.steps > 0 && n.counter >= n.steps do return false
	if !persistent_compute_observations_and_fields(n, g, random) do return false
	persistent_rule_scan(n, g, ctx)
	n.last_matched_turn = ctx.counter
	if n.match_count == 0 do return false
	if trace, ok := os.lookup_env("MJ_TRACE_BRANCH", context.temp_allocator); ok && trace == "1" {
		fmt.eprintf("TRACE Odin turn=%d node=%d kind=all matchCount=%d\n", ctx.counter, n.debug_index, n.match_count)
	}

	if n.potentials != nil {
		persistent_all_apply_potentials(n, g, random, ctx)
	} else {
		shuffle := make([]int, n.match_count)
		for i in 0..<len(shuffle) {
			j := int(mj_random_next_max(random, i32(i + 1)))
			shuffle[i] = shuffle[j]
			shuffle[j] = i
		}
		defer delete(shuffle)

		for k in 0..<len(shuffle) {
			m := n.matches[shuffle[k]]
			si := m.x + m.y * g.mx + m.z * g.mx * g.my
			n.match_mask[m.r][si] = false
			persistent_all_fit(g, &n.rules[m.r], m.x, m.y, m.z, n.all_mask, &ctx.changes)
		}
	}

	start := ctx.first[n.last_matched_turn]
	for ci := start; ci < len(ctx.changes); ci += 1 {
		c := ctx.changes[ci]
		n.all_mask[c.x + c.y * g.mx + c.z * g.mx * g.my] = false
	}
	n.counter += 1
	n.match_count = 0
	return true
}


persistent_all_apply_potentials :: proc(n: ^Persistent_Node, g: ^Grid, random: ^MJRandom, ctx: ^Exec_Context) {
	Pair :: struct {idx: int, key: f64}
	list := make([dynamic]Pair)
	defer delete(list)
	first_h := 0
	first_set := false
	for m_idx in 0..<n.match_count {
		m := n.matches[m_idx]
		h, ok := field_delta_pointwise(g.state, &n.rules[m.r], m.x, m.y, m.z, n.fields, n.potentials, len(g.characters), g.mx, g.my)
		if ok {
			if !first_set { first_h = h; first_set = true }
			append(&list, Pair{m_idx, field_key(h, first_h, n.temperature, random)})
		}
	}
	// stable insertion sort descending to match LINQ OrderBy(-key) for unique random keys.
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
		m := n.matches[p.idx]
		si := m.x + m.y * g.mx + m.z * g.mx * g.my
		n.match_mask[m.r][si] = false
		persistent_all_fit(g, &n.rules[m.r], m.x, m.y, m.z, n.all_mask, &ctx.changes)
	}
}

persistent_all_fit :: proc(g: ^Grid, rule: ^Rule, x, y, z: int, mask: []bool, changes: ^[dynamic]Cell) {
	for dz in 0..<rule.omz {
		for dy in 0..<rule.omy {
			for dx in 0..<rule.omx {
				value := rule.output[dx + dy * rule.omx + dz * rule.omx * rule.omy]
				if value != 0xff && mask[x + dx + (y + dy) * g.mx + (z + dz) * g.mx * g.my] do return
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

persistent_one_go :: proc(n: ^Persistent_Node, g: ^Grid, random: ^MJRandom, ctx: ^Exec_Context) -> bool {
	if len(n.rules) == 0 do return false
	if n.steps > 0 && n.counter >= n.steps do return false
	if !persistent_compute_observations_and_fields(n, g, random) do return false
	if n.last_matched_turn >= 0 {
		start := ctx.first[n.last_matched_turn]
		for ci := start; ci < len(ctx.changes); ci += 1 {
			c := ctx.changes[ci]
			value := g.state[c.x + c.y * g.mx + c.z * g.mx * g.my]
			for r in 0..<len(n.rules) {
				rule := &n.rules[r]
				for shift in rule.ishifts[value] {
					sx := c.x - shift.x
					sy := c.y - shift.y
					sz := c.z - shift.z
					persistent_one_try_add(g, n, r, sx, sy, sz)
				}
			}
		}
	} else {
		n.match_count = 0
		for r in 0..<len(n.match_mask) {
			for i in 0..<len(n.match_mask[r]) do n.match_mask[r][i] = false
		}
		for r in 0..<len(n.rules) {
			rule := &n.rules[r]
			for z := rule.imz - 1; z < g.mz; z += rule.imz {
				for y := rule.imy - 1; y < g.my; y += rule.imy {
					for x := rule.imx - 1; x < g.mx; x += rule.imx {
						value := g.state[x + y * g.mx + z * g.mx * g.my]
						for shift in rule.ishifts[value] {
							persistent_one_try_add(g, n, r, x - shift.x, y - shift.y, z - shift.z)
						}
					}
				}
			}
		}
	}
	n.last_matched_turn = ctx.counter

	if n.trajectory != nil {
		if n.counter >= len(n.trajectory) do return false
		copy(g.state, n.trajectory[n.counter])
		n.counter += 1
		return true
	}

	if n.potentials != nil {
		return persistent_one_go_potentials(n, g, random, ctx)
	}

	for n.match_count > 0 {
		match_count_before := n.match_count
		arg := int(mj_random_next_max(random, i32(n.match_count)))
		m := n.matches[arg]
		si := m.x + m.y * g.mx + m.z * g.mx * g.my
		n.match_mask[m.r][si] = false
		n.matches[arg] = n.matches[n.match_count - 1]
		n.match_count -= 1

		if grid_matches(g, &n.rules[m.r], m.x, m.y, m.z) {
			if trace, ok := os.lookup_env("MJ_TRACE_MARKOV", context.temp_allocator); ok && trace == "1" {
				fmt.eprintf("TRACE Odin turn=%d node=%d rule=%d x=%d y=%d z=%d matchCount=%d matchIndex=%d\n", ctx.counter, n.debug_index, m.r, m.x, m.y, m.z, match_count_before, arg)
			}
			if trace, ok := os.lookup_env("MJ_TRACE_BRANCH", context.temp_allocator); ok && trace == "1" {
				fmt.eprintf("TRACE Odin turn=%d node=%d kind=one rule=%d x=%d y=%d z=%d matchCount=%d matchIndex=%d\n", ctx.counter, n.debug_index, m.r, m.x, m.y, m.z, match_count_before, arg)
			}
			one_apply_with_context(g, &n.rules[m.r], m.x, m.y, m.z, &ctx.changes)
			n.counter += 1
			return true
		}
	}
	return false
}

persistent_one_go_potentials :: proc(n: ^Persistent_Node, g: ^Grid, random: ^MJRandom, ctx: ^Exec_Context) -> bool {
	if n.observations != nil && observations_goal_reached(g.state, n.future) {
		n.future_computed = false
		return false
	}
	max_key := -1000.0
	argmax := -1
	first_h := 0
	first_set := false
	for k := 0; k < n.match_count; k += 1 {
		m := n.matches[k]
		si := m.x + m.y * g.mx + m.z * g.mx * g.my
		if !grid_matches(g, &n.rules[m.r], m.x, m.y, m.z) {
			n.match_mask[m.r][si] = false
			n.matches[k] = n.matches[n.match_count - 1]
			n.match_count -= 1
			k -= 1
		} else {
			h, ok := field_delta_pointwise(g.state, &n.rules[m.r], m.x, m.y, m.z, n.fields, n.potentials, len(g.characters), g.mx, g.my)
			if !ok do continue
			if !first_set { first_h = h; first_set = true }
			key := field_key(h, first_h, n.temperature, random)
			if key > max_key { max_key = key; argmax = k }
		}
	}
	if argmax < 0 do return false
	m := n.matches[argmax]
	one_apply_with_context(g, &n.rules[m.r], m.x, m.y, m.z, &ctx.changes)
	n.counter += 1
	return true
}

persistent_compute_observations_and_fields :: proc(n: ^Persistent_Node, g: ^Grid, random: ^MJRandom) -> bool {
	if n.observations != nil && !n.future_computed {
		if !observations_compute_future_set_present(n.future, g.state, n.observations) do return false
		n.future_computed = true
		if n.search {
			if n.trajectory != nil { search_destroy_trajectory(n.trajectory); n.trajectory = nil }
			tries := 1
			if n.limit >= 0 do tries = 20
			for k := 0; k < tries && n.trajectory == nil; k += 1 {
				n.trajectory = search_run(g.state, n.future, n.rules[:], g.mx, g.my, g.mz, len(g.characters), n.kind == .All, n.limit, n.depth_coefficient, mj_random_next(random))
			}
		} else {
			observations_compute_backward_potentials(n.potentials, n.future, g.mx, g.my, g.mz, len(g.characters), n.rules[:])
		}
	}
	if n.potentials == nil || n.observations != nil do return true
	any_success := false
	any_computation := false
	state_len := len(g.state)
	for c in 0..<len(n.fields) {
		f := &n.fields[c]
		if f.present && (n.counter == 0 || f.recompute) {
			success := field_compute(f, n.potentials[c * state_len:(c + 1) * state_len], g)
			if !success && f.essential do return false
			any_success = any_success || success
			any_computation = true
		}
	}
	if any_computation && !any_success do return false
	return true
}

persistent_one_try_add :: proc(g: ^Grid, n: ^Persistent_Node, r, sx, sy, sz: int) {
	rule := &n.rules[r]
	if sx < 0 || sy < 0 || sz < 0 || sx + rule.imx > g.mx || sy + rule.imy > g.my || sz + rule.imz > g.mz do return
	si := sx + sy * g.mx + sz * g.mx * g.my
	if !n.match_mask[r][si] && grid_matches(g, rule, sx, sy, sz) {
		n.match_mask[r][si] = true
		m := Match{r, sx, sy, sz}
		if n.match_count < len(n.matches) {
			n.matches[n.match_count] = m
		} else {
			append(&n.matches, m)
		}
		n.match_count += 1
	}
}

one_apply_with_context :: proc(g: ^Grid, rule: ^Rule, x, y, z: int, changes: ^[dynamic]Cell) {
	for dz in 0..<rule.omz {
		for dy in 0..<rule.omy {
			for dx in 0..<rule.omx {
				new_value := rule.output[dx + dy * rule.omx + dz * rule.omx * rule.omy]
				if new_value != 0xff {
					sx := x + dx
					sy := y + dy
					sz := z + dz
					si := sx + sy * g.mx + sz * g.mx * g.my
					old_value := g.state[si]
					if old_value != new_value {
						g.state[si] = new_value
						append(changes, Cell{sx, sy, sz})
					}
				}
			}
		}
	}
}
