package markov_junior

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

main :: proc() {
	model := ""
	amount := 1
	output := "output"
	format := "text"
	steps := -1
	model_index := -1

	for i in 1..<len(os.args) {
		arg := os.args[i]
		if strings.has_prefix(arg, "--amount=") {
			parsed, ok := strconv.parse_int(arg[9:])
			if ok {
				amount = int(parsed)
			}
		} else if strings.has_prefix(arg, "--steps=") {
			parsed, ok := strconv.parse_int(arg[8:])
			if ok {
				steps = int(parsed)
			}
		} else if strings.has_prefix(arg, "--model-index=") {
			parsed, ok := strconv.parse_int(arg[14:])
			if ok {
				model_index = int(parsed)
			}
		} else if strings.has_prefix(arg, "--output=") {
			output = arg[9:]
		} else if strings.has_prefix(arg, "--format=") {
			format = arg[9:]
		} else if len(model) == 0 {
			model = arg
		}
	}

	if len(model) > 0 {
		if run_xml_one_model(model, amount, output, format, steps, model_index) {
			return
		}
	}

	fmt.println("MarkovJunior Odin bootstrap")
	fmt.println("Deterministic MJRandom test vector:")

	r := mj_random_init(42)
	fmt.printf("seed 42 Next: %d %d %d %d %d\n", mj_random_next(&r), mj_random_next(&r), mj_random_next(&r), mj_random_next(&r), mj_random_next(&r))

	r = mj_random_init(42)
	fmt.printf("seed 42 Next(10): %d %d %d %d %d\n", mj_random_next_max(&r, 10), mj_random_next_max(&r, 10), mj_random_next_max(&r, 10), mj_random_next_max(&r, 10), mj_random_next_max(&r, 10))

	r = mj_random_init(42)
	fmt.printf("seed 42 Double: %.17g %.17g %.17g\n", mj_random_next_f64(&r), mj_random_next_f64(&r), mj_random_next_f64(&r))
}
