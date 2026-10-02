package markov_junior

import xml "core:encoding/xml"
import "core:math"

ConvChain_State :: struct {
	n: int,
	steps: int,
	counter: int,
	temperature: f64,
	weights: []f64,
	c0, c1: u8,
	substrate_color: u8,
	substrate: []bool,
}

convchain_load :: proc(doc: ^xml.Document, id: xml.Element_ID, g: ^Grid, symmetry: string) -> ConvChain_State {
	// XML/PNG loading is intentionally unavailable in the component boundary.
	// Runtime component execution builds ConvChain_State from MJIR op 108 instead.
	return ConvChain_State{}
}

convchain_destroy :: proc(c: ^ConvChain_State) {
	if c.weights != nil do delete(c.weights)
	if c.substrate != nil do delete(c.substrate)
}

convchain_go :: proc(c: ^ConvChain_State, g: ^Grid, random: ^MJRandom) -> bool {
	if c.steps > 0 && c.counter >= c.steps do return false
	mx := g.mx; my := g.my
	if c.counter == 0 {
		any := false
		for i in 0..<len(c.substrate) do if g.state[i] == c.substrate_color {
			if mj_random_next_max(random, 2) == 0 {
				g.state[i] = c.c0
			} else {
				g.state[i] = c.c1
			}
			c.substrate[i] = true
			any = true
		}
		c.counter += 1
		return any
	}
	for k in 0..<len(g.state) {
		r := int(mj_random_next_max(random, i32(len(g.state))))
		if !c.substrate[r] do continue
		x := r % mx; y := r / mx
		q := 1.0
		for sy := y - c.n + 1; sy <= y + c.n - 1; sy += 1 do for sx := x - c.n + 1; sx <= x + c.n - 1; sx += 1 {
			ind := 0; difference := 0
			for dy in 0..<c.n do for dx in 0..<c.n {
				X := sx + dx
				if X < 0 { X += mx } else if X >= mx { X -= mx }
				Y := sy + dy
				if Y < 0 { Y += my } else if Y >= my { Y -= my }
				value := g.state[X + Y * mx] == c.c1
				power := 1 << uint(dy * c.n + dx)
				if value do ind += power
				if X == x && Y == y {
					if value { difference = power } else { difference = -power }
				}
			}
			q *= c.weights[ind - difference] / c.weights[ind]
		}
		if q >= 1 {
			convchain_toggle(c, g, r); continue
		}
		if c.temperature != 1 do q = math.pow(q, 1.0 / c.temperature)
		if q > mj_random_next_f64(random) do convchain_toggle(c, g, r)
	}
	c.counter += 1
	return true
}

convchain_toggle :: proc(c: ^ConvChain_State, g: ^Grid, i: int) {
	if g.state[i] == c.c0 {
		g.state[i] = c.c1
	} else {
		g.state[i] = c.c0
	}
}
