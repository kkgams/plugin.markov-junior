# plugin.markov-junior

Deterministic MarkovJunior grid generation for [GAMS](https://github.com/kkgams/gams).

| Item | Source | Original work | License |
| --- | --- | --- | --- |
| MarkovJunior component | `plugins/markov-junior.comp/` | [MarkovJunior, Maxim Gumin](https://github.com/mxgmn/MarkovJunior), Odin port and GAMS integration | [LICENSE](LICENSE), [original terms](LICENSES/), [attribution](MARKOV-UPSTREAM-ATTRIBUTIONS.md) |
| XML/MJIR compiler and resources | `script/`, `packages/util/markov-junior/`, component compiler/docs/tests | MarkovJunior contributors and GAMS contributors | [NOTICE](NOTICE), [terms](LICENSES/) |

## Development

Use the pinned Odin/C/WASI and Node toolchain: `nix develop --command make <target>`.

| Command | Purpose |
| --- | --- |
| `make build` | Compile the component with embedded complete terms. |
| `make test` | Run existing dependency-free XML/MJIR compiler tests. |
| `make package` | Build stable WASM, tooling ZIP, LICENSES.zip and SHA256SUMS in build.nosync/. |
| `make open` | Build and open this Project in the released macOS Apple Silicon Host. |
| `make docs` | Build pinned wiki in build.nosync/site/. |
| `make serve-docs` | Serve wiki; independent DOCS_PORT defaults to 8080. |
| `make validate-docs` | Validate wiki content. |
| `make clean` | Remove build.nosync and identified downloads; refuse tracked paths/symlinks and preserve supplied tools/Units. |

The tooling ZIP retains compiler/CLI sources, model resources, domain tests, reference tooling and complete terms; no precompiled replacement is supplied. See `plugins/markov-junior.comp/MJIR.md` and its docs for the format. Compiler tests do not execute the component or establish parity. Historical Host/reference parity tools remain available but require external resources and are not standalone coverage.

The local Files View browses Project files; it is not a generation demo. The first launch downloads pinned supporting Units; an existing Host is never updated implicitly. GUI/runtime execution is separately verified.

## API

Exports `gams:markov-junior/markov-junior@1.0.0`, world `markov-junior-plugin`. `run` consumes prepared MJIR, initial indexed cells, dimensions, seed and step limit. `create`, `step` and `dismiss` manage sessions. No filesystem imports: compile XML/PNG/VOX resources outside the component. The complete contract is `plugins/markov-junior.comp/wit/package.wit`.
