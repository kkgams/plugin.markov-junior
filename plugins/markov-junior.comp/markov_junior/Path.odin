package markov_junior

import "core:math"
import xml "core:encoding/xml"

Path_State :: struct {
	start, finish, substrate: i32,
	value: u8,
	inertia, longest, edges, vertices: bool,
}

Path_Queue_Item :: struct {
	t, x, y, z: int,
}

path_load :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid) -> Path_State {
	from := xml_attr(doc, id, "from")
	color := xml_attr(doc, id, "color", from[:1])
	return Path_State{
		start = grid_wave_string(g, from),
		value = grid_value(g, color[0]),
		finish = grid_wave_string(g, xml_attr(doc, id, "to")),
		substrate = grid_wave_string(g, xml_attr(doc, id, "on")),
		inertia = xml_attr_bool(doc, id, "inertia"),
		longest = xml_attr_bool(doc, id, "longest"),
		edges = xml_attr_bool(doc, id, "edges"),
		vertices = xml_attr_bool(doc, id, "vertices"),
	}
}

path_go :: proc(p: ^Path_State, g: ^Grid, random: ^MJRandom, changes: ^[dynamic]Cell) -> bool {
	frontier := make([dynamic]Path_Queue_Item)
	defer delete(frontier)
	starts := make([dynamic]Cell)
	defer delete(starts)
	generations := make([]int, len(g.state))
	defer delete(generations)
	for i in 0..<len(generations) do generations[i] = -1

	for z in 0..<g.mz do for y in 0..<g.my do for x in 0..<g.mx {
		i := x + y * g.mx + z * g.mx * g.my
		s := g.state[i]
		if (p.start & (i32(1) << uint(s))) != 0 do append(&starts, Cell{x, y, z})
		if (p.finish & (i32(1) << uint(s))) != 0 {
			generations[i] = 0
			append(&frontier, Path_Queue_Item{0, x, y, z})
		}
	}
	if len(starts) == 0 || len(frontier) == 0 do return false

	head := 0
	for head < len(frontier) {
		q := frontier[head]
		head += 1
		dirs := path_directions(q.x, q.y, q.z, g.mx, g.my, g.mz, p.edges, p.vertices)
		for d in dirs {
			path_push(g, p, generations, &frontier, q.t + 1, q.x + d.x, q.y + d.y, q.z + d.z)
		}
	}

	reachable := false
	for s in starts {
		if generations[s.x + s.y * g.mx + s.z * g.mx * g.my] > 0 {
			reachable = true
			break
		}
	}
	if !reachable do return false

	local := mj_random_init(mj_random_next(random))
	minv := f64(g.mx * g.my * g.mz)
	maxv := -2.0
	argmin := Cell{-1, -1, -1}
	argmax := Cell{-1, -1, -1}
	for s in starts {
		gen := generations[s.x + s.y * g.mx + s.z * g.mx * g.my]
		if gen == -1 do continue
		v := f64(gen) + 0.1 * mj_random_next_f64(&local)
		if v < minv {
			minv = v
			argmin = s
		}
		if v > maxv {
			maxv = v
			argmax = s
		}
	}

	pen := argmin
	if p.longest do pen = argmax
	dir := path_direction(p, g, pen.x, pen.y, pen.z, 0, 0, 0, generations, &local)
	pen.x += dir.x; pen.y += dir.y; pen.z += dir.z
	for generations[pen.x + pen.y * g.mx + pen.z * g.mx * g.my] != 0 {
		i := pen.x + pen.y * g.mx + pen.z * g.mx * g.my
		g.state[i] = p.value
		append(changes, pen)
		dir = path_direction(p, g, pen.x, pen.y, pen.z, dir.x, dir.y, dir.z, generations, &local)
		pen.x += dir.x; pen.y += dir.y; pen.z += dir.z
	}
	return true
}

path_push :: proc(g: ^Grid, p: ^Path_State, generations: []int, frontier: ^[dynamic]Path_Queue_Item, t, x, y, z: int) {
	i := x + y * g.mx + z * g.mx * g.my
	v := g.state[i]
	if generations[i] == -1 && ((p.substrate & (i32(1) << uint(v))) != 0 || (p.start & (i32(1) << uint(v))) != 0) {
		if (p.substrate & (i32(1) << uint(v))) != 0 do append(frontier, Path_Queue_Item{t, x, y, z})
		generations[i] = t
	}
}

path_direction :: proc(p: ^Path_State, g: ^Grid, x, y, z, dx, dy, dz: int, generations: []int, random: ^MJRandom) -> Cell {
	candidates := make([dynamic]Cell)
	defer delete(candidates)
	gen := generations[x + y * g.mx + z * g.mx * g.my]
	path_add_candidate :: proc(candidates: ^[dynamic]Cell, generations: []int, mx, my: int, x, y, z, dx, dy, dz, gen: int) {
		if generations[x + dx + (y + dy) * mx + (z + dz) * mx * my] == gen - 1 do append(candidates, Cell{dx, dy, dz})
	}

	if !p.vertices && !p.edges {
		if dx != 0 || dy != 0 || dz != 0 {
			cx := x + dx; cy := y + dy; cz := z + dz
			if p.inertia && cx >= 0 && cy >= 0 && cz >= 0 && cx < g.mx && cy < g.my && cz < g.mz && generations[cx + cy * g.mx + cz * g.mx * g.my] == gen - 1 do return Cell{dx, dy, dz}
		}
		if x > 0 do path_add_candidate(&candidates, generations, g.mx, g.my, x, y, z, -1, 0, 0, gen)
		if x < g.mx - 1 do path_add_candidate(&candidates, generations, g.mx, g.my, x, y, z, 1, 0, 0, gen)
		if y > 0 do path_add_candidate(&candidates, generations, g.mx, g.my, x, y, z, 0, -1, 0, gen)
		if y < g.my - 1 do path_add_candidate(&candidates, generations, g.mx, g.my, x, y, z, 0, 1, 0, gen)
		if z > 0 do path_add_candidate(&candidates, generations, g.mx, g.my, x, y, z, 0, 0, -1, gen)
		if z < g.mz - 1 do path_add_candidate(&candidates, generations, g.mx, g.my, x, y, z, 0, 0, 1, gen)
		return candidates[int(mj_random_next_max(random, i32(len(candidates))))]
	}

	dirs := path_directions(x, y, z, g.mx, g.my, g.mz, p.edges, p.vertices)
	for d in dirs do path_add_candidate(&candidates, generations, g.mx, g.my, x, y, z, d.x, d.y, d.z, gen)
	if p.inertia && (dx != 0 || dy != 0 || dz != 0) {
		max_scalar := -4.0
		result := Cell{-1, -1, -1}
		for c in candidates {
			noise := 0.1 * mj_random_next_f64(random)
			cos := f64(c.x * dx + c.y * dy + c.z * dz) / math.sqrt(f64((c.x * c.x + c.y * c.y + c.z * c.z) * (dx * dx + dy * dy + dz * dz)))
			if cos + noise > max_scalar {
				max_scalar = cos + noise
				result = c
			}
		}
		return result
	}
	return candidates[int(mj_random_next_max(random, i32(len(candidates))))]
}

path_directions :: proc(x, y, z, mx, my, mz: int, edges, vertices: bool) -> [dynamic]Cell {
	result := make([dynamic]Cell, 0, 26, context.temp_allocator)
	if mz == 1 {
		if x > 0 do append(&result, Cell{-1, 0, 0})
		if x < mx - 1 do append(&result, Cell{1, 0, 0})
		if y > 0 do append(&result, Cell{0, -1, 0})
		if y < my - 1 do append(&result, Cell{0, 1, 0})
		if edges {
			if x > 0 && y > 0 do append(&result, Cell{-1, -1, 0})
			if x > 0 && y < my - 1 do append(&result, Cell{-1, 1, 0})
			if x < mx - 1 && y > 0 do append(&result, Cell{1, -1, 0})
			if x < mx - 1 && y < my - 1 do append(&result, Cell{1, 1, 0})
		}
		return result
	}
	if x > 0 do append(&result, Cell{-1, 0, 0})
	if x < mx - 1 do append(&result, Cell{1, 0, 0})
	if y > 0 do append(&result, Cell{0, -1, 0})
	if y < my - 1 do append(&result, Cell{0, 1, 0})
	if z > 0 do append(&result, Cell{0, 0, -1})
	if z < mz - 1 do append(&result, Cell{0, 0, 1})
	if edges {
		if x > 0 && y > 0 do append(&result, Cell{-1, -1, 0})
		if x > 0 && y < my - 1 do append(&result, Cell{-1, 1, 0})
		if x < mx - 1 && y > 0 do append(&result, Cell{1, -1, 0})
		if x < mx - 1 && y < my - 1 do append(&result, Cell{1, 1, 0})
		if x > 0 && z > 0 do append(&result, Cell{-1, 0, -1})
		if x > 0 && z < mz - 1 do append(&result, Cell{-1, 0, 1})
		if x < mx - 1 && z > 0 do append(&result, Cell{1, 0, -1})
		if x < mx - 1 && z < mz - 1 do append(&result, Cell{1, 0, 1})
		if y > 0 && z > 0 do append(&result, Cell{0, -1, -1})
		if y > 0 && z < mz - 1 do append(&result, Cell{0, -1, 1})
		if y < my - 1 && z > 0 do append(&result, Cell{0, 1, -1})
		if y < my - 1 && z < mz - 1 do append(&result, Cell{0, 1, 1})
	}
	if vertices {
		if x > 0 && y > 0 && z > 0 do append(&result, Cell{-1, -1, -1})
		if x > 0 && y > 0 && z < mz - 1 do append(&result, Cell{-1, -1, 1})
		if x > 0 && y < my - 1 && z > 0 do append(&result, Cell{-1, 1, -1})
		if x > 0 && y < my - 1 && z < mz - 1 do append(&result, Cell{-1, 1, 1})
		if x < mx - 1 && y > 0 && z > 0 do append(&result, Cell{1, -1, -1})
		if x < mx - 1 && y > 0 && z < mz - 1 do append(&result, Cell{1, -1, 1})
		if x < mx - 1 && y < my - 1 && z > 0 do append(&result, Cell{1, 1, -1})
		if x < mx - 1 && y < my - 1 && z < mz - 1 do append(&result, Cell{1, 1, 1})
	}
	return result
}
