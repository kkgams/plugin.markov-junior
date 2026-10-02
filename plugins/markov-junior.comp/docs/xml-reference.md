# MarkovJunior XML Reference

This reference describes the MarkovJunior XML model format used by `plugins/markov-junior.comp`.

For each tag it lists attributes, allowed contents, and a short description.

## Document shape

A MarkovJunior model document is a generator program. Its root is one of the node tags below, usually `<one>`, `<all>`, `<prl>`, `<markov>`, `<sequence>`, `<convolution>`, `<convchain>`, or `<wfc>`.

## Pattern syntax

Inline patterns are strings used by `in` and `out` attributes.

- Characters are grid symbols from `values`, union symbols declared with `<union>`, or `*`.
- `/` separates rows on the y axis: `BBB/BWB`.
- A space separates z layers in 3D patterns: `AAA/ABA CCC/CBC`.
- Input patterns may use union symbols and `*` for any value. Example: `<union symbol="X" values="BW"/>` makes `X` mean either `B` or `W`, so `in="XRR"` matches `BRR` and `WRR`.
- Output patterns use concrete values; `*` means "leave this cell unchanged".

## Common concepts

### Grid-bearing elements

`<one>`, `<all>`, `<prl>`, `<markov>`, `<sequence>`, `<map>`, and `<wfc>` may create/load a grid when they are used as roots or as grid-producing nodes.

Attributes:

- `values = STRING` — required. Ordered list of allowed cell symbols. The first symbol is the clear/default value.
- `folder = STRING` — optional. Resource folder under `resources/rules/` for rule `fin`, `fout`, and `file` resources.
- `transparent = STRING` — optional. Values treated as transparent by rendering/output helpers.
- `origin = BOOL` — root only. If true, initializes the center cell with the second `values` symbol.
- `symmetry = SYMMETRY` — optional. Default is inherited from the parent or full symmetry at the root.

### Symmetry values

2D symmetry values:

- `()` — identity only.
- `(x)` — mirror on x.
- `(y)` — mirror on y.
- `(x)(y)` — x/y mirrors.
- `(xy+)` — rotations only.
- `(xy)` — full square symmetry.

3D symmetry values:

- `()` — identity only.
- `(x)` — x reflection subset.
- `(z)` — z reflection subset.
- `(xy)` — square-like rotations/reflections in xy.
- `(xyz+)` — cube rotations only.
- `(xyz)` — full cube symmetry.

### Shared node contents

Node tags are:

```text
one | all | prl | markov | sequence | path | map | convolution | convchain | wfc
```

Branch nodes (`markov`, `sequence`, `map`, `wfc`) may contain child node tags. Rule nodes (`one`, `all`, `prl`) do not contain child nodes; they contain rules/fields/observations.

## `<one>` - Apply one random matching rule per step

Attributes:

- grid-bearing attributes when used as a root.
- `symmetry = SYMMETRY`
- `steps = INT` — max applications for this node; `0` means unlimited until no match.
- `temperature = FLOAT` — used when field/observation potentials guide rule choice.
- `search = BOOL` — enable state-space search for observations.
- `limit = INT` — search state limit; used when `search="True"`.
- `depthCoefficient = FLOAT` — search ordering interpolation; default `0.5`.

Contents:

- `rule*`
- `field*`
- `observe*`
- `union*` may be present anywhere outside nested `markov`/`sequence` boundaries and is collected for the grid.

Example:

```xml
<one values="BW" in="B" out="W" steps="10"/>
```

Description:

Finds all matches, chooses one match/rule according to randomness and optional fields/observations, applies it, then returns success. Stops when `steps` is reached or no applicable match remains.

## `<all>` - Apply a non-overlapping set of matches per step

Attributes:

- same as `<one>`.

Contents:

- `rule*`
- `field*`
- `observe*`
- `union*`

Description:

Like `<one>`, but applies many compatible/non-overlapping matches in one interpreter step.

## `<prl>` - Apply matches in parallel

Attributes:

- same as `<one>`.

Contents:

- `rule*`
- `field*`
- `observe*`
- `union*`

Description:

Parallel rule node. Similar to `<all>`, but applies matches independently and does not care about rule overlaps. Often faster and often equivalent to `<all>` for cellular-automata-like updates.

## `<rule>` - Pattern rewrite rule

Attributes:

- `in = PATTERN` — inline input pattern.
- `out = PATTERN` — inline output pattern.
- `fin = STRING` — input pattern resource name, loaded from `resources/rules[/folder]/<name>.png` or `.vox`.
- `fout = STRING` — output pattern resource name.
- `file = STRING` — glued input+output resource; left half is input, right half is output.
- `legend = STRING` — symbol legend for PNG/VOX resource colors.
- `p = FLOAT` — application probability. Defaults to `1.0`.
- `symmetry = SYMMETRY` — optional per-rule symmetry expansion.

Contents:

- none

Description:

Defines a rewrite from an input pattern to an output pattern. Inside `<one>`, `<all>`, and `<prl>`, `in`/`out` sizes must match. Inside `<map>`, input and output pattern sizes may differ because the output goes to a new grid.

## `<union>` - Name a set of values

Attributes:

- `symbol = CHAR` — new input-only symbol.
- `values = STRING` — cell symbols included in this union.

Contents:

- none

Description:

Defines a symbolic character usable in input patterns and path/field waves. The `symbol` is a single character chosen by the model author; it does not need to appear in `values`.

Example:

```xml
<one values="BWR">
  <union symbol="X" values="BW"/>
  <rule in="XR" out="RR"/>
</one>
```

Here `X` is a union symbol. The rule input `XR` matches both `BR` and `WR`. `*` is a built-in union meaning all values.

## `<field>` - Distance field for guided rule choice

Attributes:

- `for = CHAR` — value whose placement this field scores.
- `on = STRING` — substrate values through which distance can propagate.
- `to = STRING` — target values with zero potential.
- `from = STRING` — inverse form of `to`; marks zero-potential values and reverses scoring.
- `recompute = BOOL` — recompute every step instead of only at the start.
- `essential = BOOL` — fail node if the field cannot be computed.

Contents:

- none

Example:

```xml
<one values="BWR" temperature="0.1">
  <field for="W" on="BWR" to="R"/>
  <rule in="B" out="W"/>
</one>
```

This computes distance to `R` cells through `B`, `W`, and `R` cells. When the rule can place `W` in several `B` cells, the field biases placement toward cells closer to `R`.

Description:

Builds a breadth-first distance field used to bias rule applications toward or away from target values.

## `<observe>` - Future-state constraint

Attributes:

- `value = CHAR` — present value being constrained.
- `to = STRING` — allowed future values.
- `from = CHAR` — optional replacement value used immediately before inference; defaults to `value`.

Contents:

- none

Description:

Adds an inference constraint to a `<one>` or `<all>` node. With `search="False"`, the node follows a propagation field greedily. With `search="True"`, it searches the state graph using that field as a heuristic.

## `<markov>` - Repeating branch

Attributes:

- grid-bearing attributes when used as a root.
- `symmetry = SYMMETRY`

Contents:

- node tags: `(one | all | prl | markov | sequence | path | map | convolution | convchain | wfc)*`
- `union*`

Description:

Runs child nodes as a Markov process. On each call it starts from the first child again and succeeds if any child succeeds. Useful for loops and repeated sequences.

Difference from `<sequence>`: `<markov>` restarts child selection from the beginning every interpreter step. If an earlier child can still make progress, later children may not run yet. Use it when the child list should repeat until no child can apply.

## `<sequence>` - Ordered branch

Attributes:

- grid-bearing attributes when used as a root.
- `symmetry = SYMMETRY`

Contents:

- node tags: `(one | all | prl | markov | sequence | path | map | convolution | convchain | wfc)*`
- `union*`

Description:

Runs child nodes in order. A child branch may take over execution until it completes; then the sequence advances.

Difference from `<markov>`: `<sequence>` remembers its current child and continues forward. After child 1 finishes, it moves to child 2 instead of starting over at child 1. Use it for fixed phases such as "grow caves, then smooth, then add paths".

## `<path>` - Draw a path through a substrate

Attributes:

- `from = STRING` — start values.
- `to = STRING` — finish/goal values.
- `on = STRING` — substrate values the path may travel through.
- `color = CHAR` — value written along the path; defaults to first char of `from`.
- `inertia = BOOL` — prefer continuing in the previous direction.
- `longest = BOOL` — choose a longest reachable start instead of shortest.
- `edges = BOOL` — allow diagonal edge-neighbor movement.
- `vertices = BOOL` — in 3D, allow corner/vertex-neighbor movement.

Contents:

- none

Description:

Computes distances from `to`, chooses a reachable `from`, and paints a path through `on` cells.

## `<map>` - Transform current grid into a new grid

Attributes:

- `scale = "NX NY NZ"` — required. Each component is an integer or fraction like `2` or `1/2`.
- grid-bearing attributes for the new grid, especially `values`.
- `symmetry = SYMMETRY`

Contents:

- `rule*`
- child node tags: `(one | all | prl | markov | sequence | path | map | convolution | convchain | wfc)*`
- `union*`

Description:

Creates a new grid scaled from the current grid, applies mapping rules from old grid to new grid, switches the interpreter to the new grid, then runs child nodes on that new grid.

## `<convolution>` - Neighborhood-count cellular update

Attributes:

- `neighborhood = VonNeumann | Moore | NoCorners` — required. `Moore` is 2D only; `NoCorners` is 3D.
- `periodic = BOOL` — wrap edges.
- `steps = INT` — max update steps; default `-1` means unlimited until no change.

Contents:

- `rule*`; if omitted, the `<convolution>` tag itself acts as one rule.

Rule attributes on `<rule>` or inline `<convolution>`:

- `in = CHAR` — current cell value required.
- `out = CHAR` — new value to write.
- `values = STRING` — values to count in the neighborhood.
- `sum = INTERVALS` — accepted neighbor counts, e.g. `3`, `2,3`, `1..4`.
- `p = FLOAT` — update probability.

Description:

For every cell, counts neighboring values using the selected kernel and applies the first matching convolution rule.

## `<convchain>` - ConvChain binary texture sampler

Attributes:

- `sample = STRING` — PNG sample name under `resources/samples/`.
- `n = INT` — pattern size. Defaults to `3`.
- `steps = INT` — number of MCMC steps; default `-1` means unlimited.
- `temperature = FLOAT` — sampler temperature. Defaults to `1.0`.
- `black = CHAR` — grid value for black/false sample cells.
- `white = CHAR` — grid value for white/true sample cells.
- `on = CHAR` — substrate value to replace with sampled black/white cells.
- `symmetry = SYMMETRY` — controls sample pattern symmetries.

Contents:

- none

Description:

Initializes all `on` cells randomly as `black`/`white`, then samples binary texture patterns learned from the sample image.

## `<wfc sample="...">` - Overlapping WFC

Attributes:

- `sample = STRING` — PNG sample name under `resources/samples/`.
- `n = INT` — pattern size. Defaults to `3`.
- `periodicInput = BOOL` — whether sample patterns wrap. Defaults to `True`.
- `symmetry = SYMMETRY` — sample pattern symmetries.
- `shannon = BOOL` — use Shannon entropy instead of remaining-pattern count.
- `tries = INT` — contradiction retry count. Defaults to `1000`.
- grid-bearing attributes for the output grid, especially `values`.

Contents:

- `rule*` — optional constraints from old-grid values to allowed output values.
- child node tags: `(one | all | prl | markov | sequence | path | map | convolution | convchain | wfc)*`

WFC constraint rule attributes:

- `in = CHAR` — value in the input/current grid.
- `out = "A|B|C"` — allowed output values or tile names separated by `|`.

Description:

Learns overlapping `n x n` patterns from a sample PNG, solves WFC over the current grid size, creates a new grid, then runs child nodes on it.

## `<wfc tileset="...">` - Tile WFC

Attributes:

- `tileset = STRING` — tileset XML name under `resources/tilesets/<tileset>.xml`.
- `tiles = STRING` — optional tile VOX folder name; defaults to `tileset`.
- `periodic = BOOL` — wrap output constraints.
- `overlap = INT` — xy overlap in output assembly. Defaults to `0`.
- `overlapz = INT` — z overlap in output assembly. Defaults to `0`.
- `shannon = BOOL` — use Shannon entropy.
- `tries = INT` — contradiction retry count. Defaults to `1000`.
- grid-bearing attributes for the output grid, especially `values`.

Contents:

- `rule*` — optional constraints from old-grid values to allowed tile names.
- child node tags: `(one | all | prl | markov | sequence | path | map | convolution | convchain | wfc)*`

Description:

Loads a tileset definition plus tile VOX files, solves tile adjacency constraints on the current grid, creates a larger assembled output grid, then runs child nodes.

## Tileset XML tags

Tileset XML files live under `resources/tilesets/` and are referenced by `<wfc tileset="...">`.

### `<set>` / tileset root

Attributes:

- `fullSymmetry = BOOL` — if true, generate full cube symmetries; otherwise square/z symmetries.

Contents:

- `tiles`
- `neighbors`

Description:

The original code reads the root element generically; examples commonly use a tileset root containing `<tiles>` and `<neighbors>`.

### `<tiles>`

Contents:

- `tile*`

Description:

Container for tile declarations.

### `<tile>`

Attributes:

- `name = STRING` — VOX file basename under the tile folder.
- `weight = FLOAT` — WFC selection weight. Defaults to `1.0`.

Contents:

- none

Description:

Declares one tile resource and its statistical weight.

### `<neighbors>`

Contents:

- `neighbor*`

Description:

Container for allowed adjacency declarations.

### `<neighbor>`

Attributes:

- `left = TILE_REF`, `right = TILE_REF` — allowed horizontal adjacency.
- `top = TILE_REF`, `bottom = TILE_REF` — allowed vertical/z adjacency in non-full-symmetry tilesets.

`TILE_REF` is either a tile name or an operation prefix plus tile name, e.g. `x TileName`, `zy TileName`. Operations are rotations around axes (`x`, `y`, `z`) applied to the named tile.

Contents:

- none

Description:

Declares an allowed neighbor relation. The loader expands symmetric/reflected variants depending on `fullSymmetry` and the relation form.

## Parent/child quick table

| Tag | May appear inside | May contain |
| --- | --- | --- |
| `one` | document root, `markov`, `sequence`, `map`, `wfc` | `rule*`, `field*`, `observe*`, `union*` |
| `all` | document root, `markov`, `sequence`, `map`, `wfc` | `rule*`, `field*`, `observe*`, `union*` |
| `prl` | document root, `markov`, `sequence`, `map`, `wfc` | `rule*`, `field*`, `observe*`, `union*` |
| `rule` | `one`, `all`, `prl`, `map`, `convolution`, `wfc` | none |
| `field` | `one`, `all`, `prl` | none |
| `observe` | `one`, `all`, `prl` | none |
| `union` | grid-bearing model XML elements outside nested `markov`/`sequence` boundaries | none |
| `markov` | document root, `markov`, `sequence`, `map`, `wfc` | node tags, `union*` |
| `sequence` | document root, `markov`, `sequence`, `map`, `wfc` | node tags, `union*` |
| `path` | document root, `markov`, `sequence`, `map`, `wfc` | none |
| `map` | document root, `markov`, `sequence`, `map`, `wfc` | `rule*`, node tags, `union*` |
| `convolution` | document root, `markov`, `sequence`, `map`, `wfc` | `rule*` or inline rule attrs |
| `convchain` | document root, `markov`, `sequence`, `map`, `wfc` | none |
| `wfc` | document root, `markov`, `sequence`, `map`, `wfc` | `rule*`, node tags |
| `tiles` | tileset root | `tile*` |
| `tile` | `tiles` | none |
| `neighbors` | tileset root | `neighbor*` |
| `neighbor` | `neighbors` | none |
