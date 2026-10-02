# markov-junior.comp

Odin-backed MarkovJunior compute component for GAMS.

## Boundary

The component is intentionally pure for MVP:

- no `gams:fs` import
- no `wasi:filesystem` import yet
- no XML, PNG, or VOX file I/O inside the component
- deterministic `input -> output` execution through one exported WIT function

External tooling is responsible for compiling source assets into prepared inputs:

```text
MarkovJunior XML + resources -> MJIR + initial indexed grid -> markov-junior.comp -> final indexed grid
```

If file access is needed later, prefer standard `wasi:filesystem`; do not add `gams:fs`.

## Documentation

- `docs/xml-reference.md` is a Markdown tag/attribute reference for MarkovJunior XML, modeled after the readable BulletML reference style.

## Public API

See `wit/package.wit`.

Current MVP export:

```text
markov-junior/markov-junior::run(model-ir, initial-cells, config) -> result<grid, string>
```

`initial-cells` and result `cells` are indexed `u8` cell values. The `values` string maps each index to the original MarkovJunior symbol.

## MJIR MVP

The first checked-in MJIR format is a tracer-bullet format, not the final complete MarkovJunior IR. It exists to prove the component build, WIT call path, deterministic execution, and e2e/parity test shape.

`compiler/xml-to-mjir.mjs` is the reusable XML→MJIR entry point. It currently supports root `<one>`, `<all>`, `<prl>`, root `<markov>`, and root `<sequence>` models with nested `<markov>/<sequence>` containers, resource-free `<convolution>` nodes, `<convchain>` nodes with sample PNG weights precomputed outside the component, and overlap `<wfc sample="...">` nodes with sample PNG patterns/propagators precomputed outside the component, tile `<wfc tileset="...">` nodes with tileset XML/VOX patterns/propagators precomputed outside the component, inline `in`/`out` patterns, external PNG/VOX rule resources pre-expanded by the compiler, terminal and nested `<map>` nodes (including `fin`/`fout` resources; `outputValues`/`transparent` are accepted for Odin text-output parity), or child `<rule>` patterns, `<union>` declarations, resource-free `<field>` declarations on `<one>/<all>` nodes, non-search and search `<observe>` declarations, resource-free `<path>` nodes, `values`, `origin`, `symmetry`, child `steps`, `temperature`, and rule probability `p` attributes. It emits MJIR v1 pattern rules (`op = 2`), union declarations (`op = 101`), field/temperature declarations (`op = 103/104`), observation declarations (`op = 105`), search declarations (`op = 111`), path payloads (`op = 106`), convolution payloads (`op = 107`), convchain payloads (`op = 108`), overlap WFC payloads (`op = 109`), tile WFC payloads (`op = 112`), terminal map payloads (`op = 110`), plus node/container markers (`op = 100`) when needed, and prepares initial indexed grids outside the component.

The component expands symmetries with the existing Odin rule helpers and runs the current Odin `one` / `all` / `prl` node matching/apply loops plus the copied Odin convolution, convchain, overlap WFC, and map kernels with `MJRandom`, preserving deterministic seed behavior for the supported models.

## Test strategy

Short term:

1. e2e test calls the component through GAMS runtime.
2. Test verifies deterministic `model-ir + initial grid + config -> grid` behavior.

Migration strategy:

1. Build an external compiler from existing MarkovJunior XML/resources to MJIR.
2. Generate golden outputs from the existing Odin/C# runner for all models.
3. Run the same prepared inputs through `markov-junior.comp`.
4. Compare final grids byte-for-byte.
5. Only after parity is complete, improve internals and consider generic randomness via `wasi:random`.

## Build

From GAMS repo root:

```sh
make build.nosync/plugins/markov-junior.comp.wasm
```

Run e2e and compiler unit tests:

```sh
make markov-junior.comp-test
node plugins/markov-junior.comp/test/compiler.mjs
```

Run the parity fixtures against the original MarkovJunior Odin runner:

```sh
MARKOV_JUNIOR_REPO=/Users/gook/Repos/MarkovJunior node plugins/markov-junior.comp/test/parity-root-one.mjs
```

The parity harness writes large component argument payloads to an `--args-file` consumed by the GAMS CLI, avoiding argv-size limits for large MJIR fixtures.

For CI jobs that do not have the original repo checked out, pass `--skip-missing-original` to skip parity cleanly instead of failing before component tests run.

`parity-root-one.mjs` compiles the currently supported root `<one>` inline/resource-pattern fixtures (`Basic`, `BlueNoise`, `CentralSAW`, `Growth`, `GrowthContraction`, `GrowthWalk`, `IrregularMazeGrowth`, `IrregularSAW`, `Laplace`, `MazeGrowth`, `MazeTrail`, `RainbowGrowth`, `RegularSAW`, `SelfAvoidingWalk`, `StrangeGrowth`, `Trail`) into MJIR v1, runs the original Odin CLI, extracts seeds from generated filenames, runs the component with the same seed/config, and compares final grid bytes. `parity-root-all.mjs` does the same for root `<all>` fixtures (`ParallelGrowth`, `ParallelMazeGrowth`, `PutLs`, `NestedGrowth`). `parity-root-prl.mjs` covers root `<prl>` fixtures (`ForestFire`). `parity-root-convolution.mjs` covers root `<convolution>` fixtures (`Counting`, `ForestFireCA`). `parity-root-convchain.mjs` covers `<sequence>` fixtures containing `<convchain>` nodes (`ChainDungeon`, `ChainDungeonMaze`, `ChainMaze`). `parity-root-wfc.mjs` covers overlap-WFC fixtures (`Sewers`, `WaveBrickWall`, `WaveDungeon`, `WaveFlowers`). `parity-root-markov.mjs` covers simple root `<markov>` fixtures (`Backtracker`, `Digger`, `MazeBacktracker`, `NoDeadEnds`, `PutColoredLs`, `RegularSAWRestart`, `SAWRestart`). `parity-root-sequence.mjs` covers simple root `<sequence>` fixtures including field-guided, observation-guided, path, terminal-map, nested-container, and convolution models (`Cave`, `CaveContour`, `ConnectedCaves`, `CrossCountry`, `GameOfLife`, `Hills`, `Island`, `LostCity`, `OpenCave`, `OpenCave3D`, `Rosettes`, `SelectLargeCaves`, plus the earlier sequence set). `parity-basic.mjs` remains as a compatibility shim. `parity-csharp.mjs` is a three-way parity harness that runs the original C# implementation, the Odin port, and the WASM component for the same models/seeds and compares final text grids.

Useful replay/fuzz commands:

```sh
node plugins/markov-junior.comp/test/parity-root-one.mjs --model=Basic --runs=2 --steps=10
node plugins/markov-junior.comp/test/parity-root-all.mjs --runs=1 --steps=10
node plugins/markov-junior.comp/test/parity-root-prl.mjs --runs=1 --steps=10
node plugins/markov-junior.comp/test/parity-root-markov.mjs --runs=1 --steps=10
node plugins/markov-junior.comp/test/parity-root-convolution.mjs --runs=1 --steps=10
node plugins/markov-junior.comp/test/parity-root-convchain.mjs --runs=1 --steps=10
node plugins/markov-junior.comp/test/parity-root-wfc.mjs --runs=1 --steps=10
node plugins/markov-junior.comp/test/parity-root-sequence.mjs --runs=1 --steps=10
node plugins/markov-junior.comp/test/parity-csharp.mjs --group=smoke --runs=1 --steps=10
node plugins/markov-junior.comp/test/parity-csharp-stress.mjs --group=supported --runs=3 --steps=10,50,100 --log=build.nosync/markov-junior-parity/csharp-stress/stress.jsonl
node plugins/markov-junior.comp/test/discover-supported.mjs --show-unsupported
node plugins/markov-junior.comp/test/parity-root-one.mjs --skip-missing-original
node plugins/markov-junior.comp/test/fuzz-root-one.mjs --model=Basic --runs=10 --steps=10
node plugins/markov-junior.comp/test/fuzz-root-one.mjs --model=Basic --runs=1 --steps=10 --seed=12345
```

`discover-supported.mjs` reports separate compiler-supported, fixture-ready, parity-fixtured, known-mismatch, no-generic-original-output, unlisted, needs-config, and unsupported buckets so MJIR compiler support is not confused with byte-for-byte parity coverage. Explicit fixture configs cover supported models absent from active `models.xml`. The fuzz script runs the component twice for each model/seed, checks deterministic replay and grid invariants, and prints every seed so failures can be reproduced with `--model`, `--steps`, and `--seed`. `parity-csharp-stress.mjs` runs resumable mass C#/Odin/component parity as model/steps/runs cases, writes JSONL progress records plus stdout/stderr files, skips passed cases on restart, prints progress/elapsed/ETA in stdout, and prints exact repro commands for failures.

## Stress parity runs

Use `parity-csharp-stress.mjs` for long-running migration confidence checks. It compares the original C# implementation, the Odin port, and the WASM component for each selected model/step-count case.

The harness is resumable:

- progress is appended as JSONL records to `--log`
- stdout/stderr for each case are written next to the log
- rerunning the same command skips cases already marked `pass`
- `--keep-going` records failures and continues to the next case
- failure records include an exact repro command

Quick smoke check:

```sh
nix develop -c node plugins/markov-junior.comp/test/parity-csharp-stress.mjs \
  --group=smoke \
  --runs=1 \
  --steps=10 \
  --log=build.nosync/markov-junior-parity/csharp-stress/smoke.jsonl
```

Recommended broad run:

```sh
nix develop -c node plugins/markov-junior.comp/test/parity-csharp-stress.mjs \
  --group=supported \
  --runs=3 \
  --steps=10,50,100 \
  --keep-going \
  --log=build.nosync/markov-junior-parity/csharp-stress/stress-r3-s10-50-100.jsonl
```

Larger overnight run:

```sh
nix develop -c node plugins/markov-junior.comp/test/parity-csharp-stress.mjs \
  --group=supported \
  --runs=10 \
  --steps=10,50,100,250,500 \
  --keep-going \
  --log=build.nosync/markov-junior-parity/csharp-stress/stress-r10-s10-50-100-250-500.jsonl
```

Run one specific model:

```sh
nix develop -c node plugins/markov-junior.comp/test/parity-csharp-stress.mjs \
  --model=TileDungeon \
  --runs=20 \
  --steps=10,50,100,250,500 \
  --keep-going \
  --log=build.nosync/markov-junior-parity/csharp-stress/TileDungeon-r20.jsonl
```

Run a focused set of models:

```sh
nix develop -c node plugins/markov-junior.comp/test/parity-csharp-stress.mjs \
  --models=TileDungeon,SeaVilla,ModernHouse \
  --runs=10 \
  --steps=10,100,500 \
  --keep-going \
  --log=build.nosync/markov-junior-parity/csharp-stress/tile-wfc-r10.jsonl
```

Useful log inspection:

```sh
# live progress records
tail -f build.nosync/markov-junior-parity/csharp-stress/stress-r3-s10-50-100.jsonl

# failures with repro commands
jq 'select(.status=="fail") | {time, key, repro, stdout, stderr}' \
  build.nosync/markov-junior-parity/csharp-stress/stress-r3-s10-50-100.jsonl

# summary by status
jq -r '.status' build.nosync/markov-junior-parity/csharp-stress/stress-r3-s10-50-100.jsonl | sort | uniq -c
```

Useful flags:

- `--no-build`: skip initial component/Odin rebuild when binaries are already current
- `--no-resume`: rerun cases even if they already passed in the log
- `--keep-going`: continue after failures instead of stopping at the first mismatch
