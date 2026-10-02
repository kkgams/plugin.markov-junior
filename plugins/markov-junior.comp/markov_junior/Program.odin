package markov_junior

// Port of source/Program.cs output helpers.

import "core:fmt"
import "core:os"
import "core:strings"

write_state_text :: proc(path: string, state: []u8, mx: int, my: int, mz: int, legend: string) {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	fmt.sbprintf(&builder, "MJSTATE 1\n")
	fmt.sbprintf(&builder, "size %d %d %d\n", mx, my, mz)
	fmt.sbprintf(&builder, "legend %s\n", legend)

	for z in 0..<mz {
		if mz > 1 {
			fmt.sbprintf(&builder, "z %d\n", z)
		}
		for y in 0..<my {
			for x in 0..<mx {
				idx := x + y * mx + z * mx * my
				fmt.sbprintf(&builder, "%c", legend[state[idx]])
			}
			fmt.sbprintf(&builder, "\n")
		}
	}

	_ = os.write_entire_file_from_string(path, strings.to_string(builder))
}
