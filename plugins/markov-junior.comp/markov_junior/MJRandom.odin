package markov_junior

MJRandom :: struct {
	seed_array: [56]i32,
	inext:      i32,
	inextp:     i32,
}

MJ_RANDOM_MBIG :: i32(2147483647)
MJ_RANDOM_MSEED :: i32(161803398)

mj_random_init :: proc(seed: i32) -> MJRandom {
	r: MJRandom

	subtraction: i32
	if seed == -2147483648 {
		subtraction = MJ_RANDOM_MBIG
	} else if seed < 0 {
		subtraction = -seed
	} else {
		subtraction = seed
	}

	mj := MJ_RANDOM_MSEED - subtraction
	r.seed_array[55] = mj
	mk := i32(1)

	ii := i32(0)
	for i in 1..<55 {
		ii += 21
		if ii >= 55 {
			ii -= 55
		}

		r.seed_array[ii] = mk
		mk = mj - mk
		if mk < 0 {
			mk += MJ_RANDOM_MBIG
		}

		mj = r.seed_array[ii]
	}

	for _ in 1..<5 {
		for i in 1..<56 {
			n := i + 30
			if n >= 55 {
				n -= 55
			}

			r.seed_array[i] -= r.seed_array[1 + n]
			if r.seed_array[i] < 0 {
				r.seed_array[i] += MJ_RANDOM_MBIG
			}
		}
	}

	r.inext = 0
	r.inextp = 21
	return r
}

mj_random_next :: proc(r: ^MJRandom) -> i32 {
	loc_inext := r.inext
	loc_inext += 1
	if loc_inext >= 56 {
		loc_inext = 1
	}

	loc_inextp := r.inextp
	loc_inextp += 1
	if loc_inextp >= 56 {
		loc_inextp = 1
	}

	ret_val := r.seed_array[loc_inext] - r.seed_array[loc_inextp]

	if ret_val == MJ_RANDOM_MBIG {
		ret_val -= 1
	}
	if ret_val < 0 {
		ret_val += MJ_RANDOM_MBIG
	}

	r.seed_array[loc_inext] = ret_val
	r.inext = loc_inext
	r.inextp = loc_inextp

	return ret_val
}

mj_random_next_f64 :: proc(r: ^MJRandom) -> f64 {
	return f64(mj_random_next(r)) * (1.0 / f64(MJ_RANDOM_MBIG))
}

mj_random_next_max :: proc(r: ^MJRandom, max_value: i32) -> i32 {
	assert(max_value >= 0)
	return i32(mj_random_next_f64(r) * f64(max_value))
}
