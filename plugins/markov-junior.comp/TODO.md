# markov-junior.comp TODO

This tracks the parity-first migration of MarkovJunior into a pure GAMS WASM component.

## Current rules

- [x] No `gams:fs` import.
- [x] No filesystem access in the component MVP.
- [x] XML/resources are compiled outside the component.
- [x] Component input is `MJIR + initial-cells + run-config`.
- [x] Deterministic seed behavior uses existing `MJRandom`.
- [ ] Keep original Odin/C# outputs as parity goldens before internal improvements.

## Part 1 — component scaffold and pure API

- [x] Create `plugins/markov-junior.comp/` scaffold.
- [x] Copy Odin port into `markov_junior/` package.
- [x] Add WIT API: `run(model-ir, initial-cells, config) -> result<grid, string>`.
- [x] Add C WIT wrapper around Odin exports.
- [x] Add Odin core exports.
- [x] Build `build.nosync/plugins/markov-junior.comp.wasm` in `nix develop`.

## Part 2 — reusable XML → MJIR compiler

- [x] Add `compiler/xml-to-mjir.mjs` reusable module.
- [x] Make `test/mjir-v1.mjs` re-export compiler helpers for compatibility.
- [x] Support root `<one>` with inline `values`, `in`, `out`, `origin`, `symmetry`.
- [x] Support multi-cell 2D/3D pattern parsing syntax (`/` rows, space-separated layers).
- [x] Fix attribute parsing so `in` does not match `origin`.
- [x] Add compiler unit tests independent of the component runtime.
- [x] Support child `<rule>` elements under root `<one>`, `<all>`, and `<prl>`.
- [x] Support rule probability `p` for stochastic rules.
- [x] Support `<union>` declarations.
- [x] Add root and nested `<one>/<all>` resource-free `<field>` representation in MJIR (`op = 103`, plus `op = 104` temperature).
- [x] Add non-search `<observe>` representation in MJIR (`op = 105`).
- [x] Add resource-free `<path>` representation in MJIR (`op = 106`).
- [x] Add resource-free `<convolution>` representation in MJIR (`op = 107`).
- [x] Add resource-free `<convchain>` representation in MJIR (`op = 108`, with sample PNG weights precomputed externally).
- [x] Add resource-free overlap `<wfc sample="...">` representation in MJIR (`op = 109`, with sample PNG patterns/propagators precomputed externally).
- [x] Add terminal `<map>` representation in MJIR (`op = 110`).
- [x] Add search observation representation in MJIR (`op = 111`).
- [x] Add tile WFC representation in MJIR (`op = 112`, with tileset XML/VOX patterns and propagators precomputed externally).

## Part 3 — MJIR v1 executor

- [x] Implement legacy `op = 1` one-cell rule.
- [x] Implement `op = 2` pattern rule with dimensions and symmetry string.
- [x] Build native Odin `Rule`s from MJIR pattern bytes.
- [x] Expand symmetries via existing Odin helpers.
- [x] Run existing Odin `one` node match/apply loop with `MJRandom`.
- [x] Add MJIR node support for root `all` inline-pattern models.
- [x] Add MJIR node support for root `prl` models.
- [x] Add simple root `<markov>` container semantics for supported child nodes.
- [x] Add simple root `<sequence>` container semantics for supported child nodes.
- [x] Add root and nested `<one>/<all>` resource-free field representation and field-guided executor paths.
- [x] Add resource-free representation for non-search observations.
- [x] Add resource-free path-node executor support.
- [x] Add resource-free convolution-node executor support.
- [x] Add resource-free convchain-node executor support.
- [x] Add resource-free overlap-WFC executor support.
- [x] Add terminal map executor support.
- [x] Add resource-free representation for search observation config.
- [x] Add resource-free representation for tile-WFC data.

## Part 4 — parity fixtures

### Passing root `<one>` fixtures

- [x] `Basic.xml`
- [x] `BlueNoise.xml`
- [x] `CentralSAW.xml`
- [x] `Growth.xml`
- [x] `GrowthContraction.xml`
- [x] `GrowthWalk.xml`
- [x] `IrregularMazeGrowth.xml`
- [x] `IrregularSAW.xml`
- [x] `Laplace.xml`
- [x] `LoopErasedWalk.xml`
- [x] `MazeGrowth.xml`
- [x] `MazeTrail.xml`
- [x] `RainbowGrowth.xml`
- [x] `RandomWalk.xml`
- [x] `RegularSAW.xml`
- [x] `SelfAvoidingWalk.xml`
- [x] `StrangeGrowth.xml`
- [x] `Trail.xml`

### Passing root `<all>` inline fixtures

- [x] `ParallelGrowth.xml`
- [x] `ParallelMazeGrowth.xml`
- [x] `PutLs.xml`
- [x] `NestedGrowth.xml`

### Passing root `<prl>` fixtures

- [x] `ForestFire.xml`

### Passing root `<convolution>` fixtures

- [x] `Counting.xml`
- [x] `ForestFireCA.xml`

### Passing `<sequence>` fixtures containing `<convchain>`

- [x] `ChainDungeon.xml`
- [x] `ChainDungeonMaze.xml`
- [x] `ChainMaze.xml`

### Passing overlap-WFC fixtures

- [x] `Sewers.xml`
- [x] `WaveBrickWall.xml`
- [x] `WaveDungeon.xml`
- [x] `WaveFlowers.xml`

### Passing root `<markov>` fixtures

- [x] `Backtracker.xml`
- [x] `Digger.xml`
- [x] `GoToGradient.xml`
- [x] `KnightPatrol.xml`
- [x] `MazeBacktracker.xml`
- [x] `NoDeadEnds.xml`
- [x] `PutColoredLs.xml`
- [x] `RegularSAWRestart.xml`
- [x] `SAWRestart.xml`
- [x] `SmarterDigger.xml`

### Passing root `<sequence>` fixtures

- [x] `BacktrackerCycle.xml`
- [x] `BasicBrickWall.xml`
- [x] `BasicDijkstraDungeon.xml`
- [x] `BasicDijkstraFill.xml`
- [x] `BasicSnake.xml`
- [x] `BasicDungeonGrowth.xml`
- [x] `BernoulliPercolation.xml`
- [x] `BasicKeys.xml`
- [x] `BasicSkyline.xml`
- [x] `BasicPartitioning.xml`
- [x] `BishopParity.xml`
- [x] `BiasedGrowth.xml`
- [x] `BiasedGrowthContraction.xml`
- [x] `BiasedMazeGrowth.xml`
- [x] `BiasedVoronoi.xml`
- [x] `CarmaTower.xml`
- [x] `Cave.xml`
- [x] `CaveContour.xml`
- [x] `CentralCrawlers.xml`
- [x] `Chase.xml`
- [x] `Circuit.xml`
- [x] `CompleteSAW.xml`
- [x] `CompleteSAWSmart.xml`
- [x] `ConnectedCaves.xml`
- [x] `ConstrainedCaves.xml`
- [x] `Coupling.xml`
- [x] `Crawlers.xml`
- [x] `CrawlersChase.xml`
- [x] `CrossCountry.xml`
- [x] `Cycles.xml`
- [x] `DenseSAW.xml`
- [x] `DiagonalPath.xml`
- [x] `Division.xml`
- [x] `DijkstraDungeon.xml`
- [x] `DualRetraction.xml`
- [x] `DualRetraction3D.xml`
- [x] `DwarfPath.xml`
- [x] `DungeonGrowth.xml`
- [x] `Dwarves.xml`
- [x] `EuclideanPath.xml`
- [x] `FindLongCycle.xml`
- [x] `FireNoise.xml`
- [x] `Flowers.xml`
- [x] `Forest.xml`
- [x] `GameOfLife.xml`
- [x] `GrowthCompetition.xml`
- [x] `GrowTo.xml`
- [x] `HamiltonianPath.xml`
- [x] `HamiltonianPaths.xml`
- [x] `Hills.xml`
- [x] `Island.xml`
- [x] `Keys.xml`
- [x] `Lightning.xml`
- [x] `LoopGrowth.xml`
- [x] `LostCity.xml`
- [x] `MarchingSquares.xml`
- [x] `MazeMap.xml`
- [x] `MultiHeadedDungeon.xml`
- [x] `MultiHeadedWalk.xml`
- [x] `MultiHeadedWalkDungeon.xml`
- [x] `Noise.xml`
- [x] `NystromDungeon.xml`
- [x] `OddScale.xml`
- [x] `OddScale3D.xml`
- [x] `OpenCave.xml`
- [x] `OpenCave3D.xml`
- [x] `OrganicMechanic.xml`
- [x] `PaintCompetition.xml`
- [x] `ParallelWalk.xml`
- [x] `Percolation.xml`
- [x] `Push.xml`
- [x] `Rectangle.xml`
- [x] `RegularPath.xml`
- [x] `River.xml`
- [x] `Rosettes.xml`
- [x] `SelectLargeCaves.xml`
- [x] `SequentialSnake.xml`
- [x] `SmartSAW.xml`
- [x] `SmoothTrail.xml`
- [x] `Snake.xml`
- [x] `SnellLaw.xml`
- [x] `SoftPath.xml`
- [x] `StableCrawlers.xml`
- [x] `StairsPath.xml`
- [x] `StochasticVoronoi.xml`
- [x] `StrangeDungeon.xml`
- [x] `StrangeNoise.xml`
- [x] `StormySnellLaw.xml`
- [x] `Tetris.xml`
- [x] `Texture.xml`
- [x] `Voronoi.xml`
- [x] `Wilson.xml`
- [x] `WolfBasedApproach.xml`

### Next candidate fixtures

- [x] Root `<all>` with child `<rule>` elements: `NestedGrowth.xml`.
- [x] Union-backed sequence model: `BasicDungeonGrowth.xml`.
- [x] Sequence models with direct child `<markov>` containers: `BacktrackerCycle.xml`, `BasicBrickWall.xml`, `Flowers.xml`, `Forest.xml`, `HamiltonianPaths.xml`, `NystromDungeon.xml`, `Texture.xml`.
- [x] Diagnosed stale node boundary after nested-container open: fixed `BasicPartitioning.xml`.
- [x] Diagnosed nested sequence reset/repeat semantics: fixed `MultiHeadedWalk.xml`.
- [x] Diagnosed nested markov child `<prl>/<all>` context propagation: fixed `Tetris.xml`.
- [x] Nested `<markov>` containing `<sequence>` fixtures: `FireNoise.xml`, `HamiltonianPath.xml`, `MultiHeadedDungeon.xml`, `MultiHeadedWalkDungeon.xml`.
- [x] Discovery separates compiler-supported models whose original runner emits no generic parity output.
- [x] `BasicSnake.xml`/`Wilson.xml`/`Chase.xml` are active in the local original `models.xml` and pass Odin/C#/component parity.
- [x] Diagnosed `Division.xml`/`Dwarves.xml`: root sequence must stop when it completes instead of resetting/repeating until `max-steps`.
- [x] Explicit config metadata for models absent from active `models.xml`: `RandomWalk.xml`, `LoopErasedWalk.xml`, `BasicSkyline.xml`, `Crawlers.xml`, `GoToGradient.xml`, `ParallelWalk.xml`, `Rectangle.xml`, `SequentialSnake.xml`, `StableCrawlers.xml`, `BasicKeys.xml`.
- [x] `RandomWalk.xml` parity fixture.
- [x] `BasicKeys.xml` parity fixture.
- [x] Diagnosed `BasicKeys.xml`: nested/container `<all>` nodes must preserve persistent match state, not rescan globally each turn.
- [x] Root `<one>` with child `<field>`: `CentralSAW.xml`, `BlueNoise.xml`, `Laplace.xml`.
- [x] Root `<all>` inline-rule models.
- [x] Root `<prl>` child-rule models.
- [x] Simple `<sequence>` models composed of supported child nodes.
- [x] Simple `<markov>` models composed of supported child nodes.
- [x] Root `<sequence>` models containing `<convolution>` nodes.
- [x] Root `<convolution>` models.
- [x] `<convchain>` models with external sample PNG weight compilation.
- [x] Overlap-WFC models with external sample PNG pattern/propagator compilation.
- [x] Indexed-color PNG sample support in the external compiler for `WaveBrickWall.xml`.
- [x] External PNG/VOX rule-resource compilation for `<one>/<all>/<prl file="...">` and child `<rule file="...">`.
- [x] Terminal `<map>` models: `MarchingSquares.xml`, `MazeMap.xml`, `OddScale.xml`.
- [x] Terminal map `fout` resources: `StairsPath.xml`.
- [x] Nested-map model: `OddScale3D.xml`.
- [x] Nested-map model with text-output ignored `outputValues`/`transparent` attrs: `CarmaTower.xml`.
- [x] Fixed XML direct-child parsing for same-name nested containers (`FindLongCycle.xml`).
- [x] Fixed active nested-container resume semantics for `SmartSAW.xml`.
- [x] Diagnosed active nested container completion: reset nested runtime state before retrying parent sequence, fixing `ChainDungeon.xml` while preserving sequence regressions.
- [x] Parity runner uses GAMS CLI `--args-file` to avoid argv-size limits for large MJIR inputs like `Island.xml`.

## Part 5 — test and docs hygiene

- [x] Component e2e test through GAMS runtime.
- [x] Parity test invokes original MarkovJunior Odin CLI and compares final grid bytes.
- [x] Add resumable C#/Odin/component stress parity harness with JSONL progress logs.
- [x] `README.md` documents pure boundary, build, and parity command.
- [x] `MJIR.md` documents current v1 tracer layout and semantics.
- [x] Add this `TODO.md` continuation tracker.
- [x] Split root-one parity into `parity-root-one.mjs`; keep `parity-basic.mjs` as compatibility shim.
- [x] Add CLI filtering/replay flags: `--model`, `--models`, `--runs`, `--steps`.
- [x] Add deterministic fuzz/replay script with printed seeds: `fuzz-root-one.mjs`.
- [x] Add fixture discovery/filtering so unsupported models are reported clearly (`test/discover-supported.mjs`).
- [x] Split discovery reporting into compiler-supported, fixture-ready, parity-fixtured, known-mismatch, no-generic-original-output, unlisted, needs-config, and unsupported buckets.
- [x] Add CI-friendly parity mode that can skip if original MarkovJunior repo is absent (`--skip-missing-original`).

## Commands

From `/Users/gook/Repos/gams3`:

```sh
nix develop -c make build.nosync/plugins/markov-junior.comp.wasm
nix develop -c make markov-junior.comp-test
node plugins/markov-junior.comp/test/compiler.mjs
nix develop -c node plugins/markov-junior.comp/test/parity-basic.mjs
nix develop -c node plugins/markov-junior.comp/test/parity-root-one.mjs --model=Basic --runs=2 --steps=10
nix develop -c node plugins/markov-junior.comp/test/parity-root-all.mjs --runs=1 --steps=10
nix develop -c node plugins/markov-junior.comp/test/parity-root-prl.mjs --runs=1 --steps=10
nix develop -c node plugins/markov-junior.comp/test/parity-root-markov.mjs --runs=1 --steps=10
nix develop -c node plugins/markov-junior.comp/test/parity-root-convolution.mjs --runs=1 --steps=10
nix develop -c node plugins/markov-junior.comp/test/parity-root-convchain.mjs --runs=1 --steps=10
nix develop -c node plugins/markov-junior.comp/test/parity-root-wfc.mjs --runs=1 --steps=10
nix develop -c node plugins/markov-junior.comp/test/parity-root-sequence.mjs --runs=1 --steps=10
node plugins/markov-junior.comp/test/discover-supported.mjs --show-unsupported
nix develop -c node plugins/markov-junior.comp/test/parity-root-one.mjs --skip-missing-original
nix develop -c node plugins/markov-junior.comp/test/fuzz-root-one.mjs --model=Basic --runs=10 --steps=10
nix develop -c node plugins/markov-junior.comp/test/fuzz-root-one.mjs --model=Basic --runs=1 --steps=10 --seed=12345
```

## Latest status

Root `<one>`, `<all>`, `<prl>`, root `<convolution>`, `<convchain>` sequence models, WFC models, simple root `<markov>`, and simple/nested root `<sequence>` fixtures listed above pass byte-for-byte against the original Odin runner for 10 steps using the seed emitted in the original output filename. Root and nested field-guided fixtures, search and non-search observation fixtures, path fixtures, nested-container fixtures, root `<sequence>` models containing `<convolution>` nodes, `<convchain>` nodes, overlap-WFC nodes, and tile-WFC nodes are covered. Discovery currently reports 159 compiler-supported XML models, 159 fixture-ready models, 159 parity-fixtured models, 0 known-mismatch models, 0 no-generic-original-output models, 0 unlisted fixture-ready models, 0 compiler-supported models that need explicit config, and 0 unsupported models. Fuzz/replay testing also verifies deterministic component output for random or explicit seeds and prints reproduction commands on failure. `parity-csharp.mjs` provides a three-way C# original vs Odin port vs WASM component parity smoke/full-supported harness; the full fixture set currently passes for `--runs=1 --steps=10`.
