---
title: plugin.markov-junior
description: Deterministic grid generation and XML/MJIR compilation.
status: reference
---

# plugin.markov-junior

Deterministic MarkovJunior grid generation for [GAMS](https://github.com/kkgams/gams).

| Item | Source | Original work |
| --- | --- | --- |
| MarkovJunior component | `plugins/markov-junior.comp/` | Maxim Gumin, Odin port and GAMS integration |
| XML/MJIR compiler and resources | `script/`, `packages/util/markov-junior/` | MarkovJunior and GAMS contributors |

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
| `make clean` | Remove all of `build.nosync/`, `tools/` and `gams_modules/`, including unmarked contents; refuse tracked files and symlinks before deleting anything. |

The tooling ZIP retains compiler/CLI sources, model resources, domain tests, reference tooling and complete terms; no precompiled replacement is supplied. See `plugins/markov-junior.comp/MJIR.md` and its docs for the format. Compiler tests do not execute the component or establish parity. Historical Host/reference parity tools remain available but require external resources and are not standalone coverage.

The local Files View browses Project files; it is not a generation demo. The first launch downloads pinned supporting Units; an existing Host is never updated implicitly. GUI/runtime execution is separately verified.

## API

Exports `gams:markov-junior/markov-junior@1.0.0`, world `markov-junior-plugin`. `run` consumes prepared MJIR, initial indexed cells, dimensions, seed and step limit. `create`, `step` and `dismiss` manage sessions. No filesystem imports: compile XML/PNG/VOX resources outside the component. The complete contract is `plugins/markov-junior.comp/wit/package.wit`.
