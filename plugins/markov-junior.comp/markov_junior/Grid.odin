package markov_junior

Grid :: struct {
	state:       []u8,
	mx:          int,
	my:          int,
	mz:          int,
	characters:  string,
	folder:      string,
	union_keys:  [dynamic]u8,
	union_waves: [dynamic]i32,
}

grid_init :: proc(mx, my, mz: int, values: string, origin: bool) -> Grid {
	clean_dyn := make([dynamic]u8)
	for i in 0..<len(values) do if values[i] != ' ' do append(&clean_dyn, values[i])
	clean := string(make([]u8, len(clean_dyn)))
	copy(transmute([]u8)clean, clean_dyn[:])
	delete(clean_dyn)
	g := Grid {
		state = make([]u8, mx * my * mz),
		mx = mx,
		my = my,
		mz = mz,
		characters = clean,
	}
	if origin {
		idx := mx / 2 + (my / 2) * mx + (mz / 2) * mx * my
		g.state[idx] = 1
	}
	return g
}

grid_destroy :: proc(g: ^Grid) {
	if g.state != nil {
		delete(g.state)
	}
	if g.union_keys != nil do delete(g.union_keys)
	if g.union_waves != nil do delete(g.union_waves)
}

grid_add_union :: proc(g: ^Grid, symbol: u8, values: string) {
	wave: i32 = 0
	for i in 0..<len(values) {
		value := grid_value(g, values[i])
		if value != 0xff {
			wave |= i32(1) << uint(value)
		}
	}
	append(&g.union_keys, symbol)
	append(&g.union_waves, wave)
}

grid_value :: proc(g: ^Grid, ch: u8) -> u8 {
	for i in 0..<len(g.characters) {
		if g.characters[i] == ch {
			return u8(i)
		}
	}
	return 0xff
}

grid_wave_string :: proc(g: ^Grid, s: string) -> i32 {
	wave: i32 = 0
	for i in 0..<len(s) {
		wave |= grid_wave(g, s[i])
	}
	return wave
}

grid_wave :: proc(g: ^Grid, ch: u8) -> i32 {
	if ch == '*' {
		return (i32(1) << uint(len(g.characters))) - 1
	}
	for i in 0..<len(g.union_keys) {
		if g.union_keys[i] == ch {
			return g.union_waves[i]
		}
	}
	value := grid_value(g, ch)
	return i32(1) << uint(value)
}

grid_matches :: proc(g: ^Grid, rule: ^Rule, x, y, z: int) -> bool {
	for dz in 0..<rule.imz {
		for dy in 0..<rule.imy {
			for dx in 0..<rule.imx {
				pi := dx + dy * rule.imx + dz * rule.imx * rule.imy
				si := (x + dx) + (y + dy) * g.mx + (z + dz) * g.mx * g.my
				value := g.state[si]
				if (rule.input[pi] & (i32(1) << uint(value))) == 0 {
					return false
				}
			}
		}
	}
	return true
}
