# macro-benches

DaCapo-style OCaml macrobenchmark suite for cross-runtime comparison.
All benchmark tool sources and dependencies are vendored via
[opam-monorepo](https://github.com/tarides/opam-monorepo), ensuring
**identical source code** across all runtimes.  The only variable is
the compiler.

## Benchmarks

16 active tools, 26 benchmark programs, 14 categories.  Target runtime:
5-20s per benchmark (DaCapo sweet spot).

| Benchmark | Category | Programs | ~Runtime | Notes |
|-----------|----------|----------|----------|-------|
| **menhir** | Text processing | 3 (ocamly, sql, sysver) | 0.4-20s | |
| **cpdf** | Text/media | 4 (merge, blacktext, scale, squeeze) | 1-9s | |
| **alt-ergo** | SMT solver | 3 (fill, yyll, unsat_smt2) | 0.02-8s | |
| **coq/rocq** | Proof assistant | 1 (corelib_stress) | 44s | fib, ack, tree construction; 5.5GB RSS |
| **ahrefs-devkit** | GC stress | 4 (htmlstream, stre, network, gzip) | 1-25s | |
| **irmin** | Databases | 1 (mem_rw) | 12s | |
| **ocamlformat** | Build tools | 1 (format 16k-line file) | 5s | |
| **decompress** | Compression | 1 (zlib compress/decompress) | 5s | |
| **eio** | Concurrency | 1 (fiber stream 20M items) | 6s | OCaml ≥ 5.2 |
| **sedlex** | Text processing | 1 (tokenize 700k lines) | 5.5s | |
| **yojson** | Data formats | 1 (parse+serialize 1000x) | 5.5s | |
| **zarith** | Numerics | 1 (15000 digits of pi) | 7s | |
| **owl** | ML/Numerics | 1 (matrix/graph computation) | 2.5s | OpenBLAS |
| **pplacer** | Bioinformatics | 1 (224-test phylogenetic suite) | ~10s | GSL, sqlite3 |
| **dune-bootstrap** | Build tools | 1 (bootstrap dune from source) | ~8s | All runtimes incl. OxCaml |
| **liquidsoap-lang** | DSL compiler | 1 (parse+typecheck 50k iterations) | ~9s | Jane Street PPX (≥ 5.3) |
| **js_of_ocaml** | Compilers | — (parked) | — | findlib runtime dep + ocaml < 5.5 |

### Runtime compatibility

| Runtime | Working benchmarks |
|---------|-------------------|
| **OCaml 5.4.1** | All 16 active tools (26 programs) |
| **OCaml trunk (5.6)** | All 16 active tools — ppxlib+lwt upgraded from git |
| **OxCaml** | menhir (3), dune-bootstrap, test_decompress, zarith_pi (6 programs) |
| **OCaml 5.4.1 ± fp ± flambda** | All 16 active tools (used by `fp_flambda_macrobenchmarks.yml`) |

## Quick start

### Prerequisites

```bash
# System libraries
sudo apt install libgmp-dev libevent-dev libcurl4-openssl-dev \
                 libpcre3-dev zlib1g-dev libopenblas-dev \
                 libgsl-dev libsqlite3-dev

# opam 2.3+ (check: opam --version)
# An opam switch with dune + ocamlfind (created automatically if needed)
```

### Setup

```bash
cd ~/macro-benches
make setup          # or: bash scripts/setup-monorepo.sh
```

This runs 9 steps: pulls ~110 vendored packages, applies 12 patches,
vendors pplacer+mcl, generates rocq config/dunestrap files, and
test-builds all binaries.  Takes ~10 minutes on first run; subsequent
runs skip completed steps.

The setup is **idempotent** — safe to run multiple times without `make clean`.

### Run benchmarks

Running-ng ships two configs that consume this monorepo:

| Config | What it does | Invocations |
|---|---|---|
| `macrobenchmarks_monorepo.yml` | Cross-runtime comparison (5.4.1, trunk, OxCaml) at default GC | 1 |
| `fp_flambda_macrobenchmarks.yml` | Frame pointers × flambda 2×2 sweep (4 variants of 5.4.1) | 3 |

```bash
cd ~/running-ng
export RUNNING_MACRO_BENCH_DIR=~/macro-benches

# Default cross-runtime comparison:
CONFIG_FILE=src/running/config/macrobenchmarks_monorepo.yml \
  bash run_ocaml_bench_gc_sweep.sh

# Frame pointers × flambda (3 invocations):
CONFIG_FILE=src/running/config/fp_flambda_macrobenchmarks.yml \
  bash run_ocaml_bench_gc_sweep.sh
```

### Clean and rebuild

```bash
make clean          # Remove build artifacts (keeps vendored sources)
make clean-all      # Remove everything (duniverse/ + vendor/ + _rocq_prefix/ + _build/)
make setup          # Re-populate from lock file
```

## How it works

1. **Lock dependencies once** — `opam monorepo lock` resolves all transitive
   deps and writes `macro-benches.opam.locked` (committed to git).
2. **Pull vendored sources** — `opam monorepo pull` downloads everything into
   `duniverse/` from the lock file.  No solver, no opam install.
3. **Apply patches** — `setup-monorepo.sh` fixes version incompatibilities
   (ppxlib for 5.6, lwt for 5.6, owl C bug, batteries Gc.stat, etc.).
4. **Vendor non-opam packages** — pplacer+mcl are cloned from GitHub and
   mcl's C libraries are built via autotools.
5. **Install Rocq locally** — `dune install rocq-runtime rocq-core` into
   `_rocq_prefix/` so coqc can find its stdlib and plugins at runtime.
6. **Build with any compiler** — `dune build` compiles from local source.
   Each runtime gets its own `_build-<runtime>/` directory for isolation.

## Directory layout

```text
macro-benches/
  dune-project                 # package declarations for opam-monorepo
  dune                         # (vendored_dirs duniverse vendor)
  dune-workspace               # default context, release profile
  Makefile                     # setup / clean / clean-all targets
  macro-benches.opam.locked    # lock file (~110 packages, committed to git)
  *.opam.template              # opam-monorepo config (opam-provided, repos)

  benchmarks/                  # build scripts + input files
    menhir/                    # .mly grammar files
    cpdf/                      # .pdf test files
    alt-ergo/                  # .why + .smt2 input files
    coq/                       # .v theory files
    ahrefs-devkit/             # benchmark .ml source files
    irmin/                     # irmin_mem_rw.ml
    ocamlformat/               # workload.ml + workload_5x.ml
    decompress/                # test_decompress.ml
    eio/                       # eio_bench.ml
    sedlex/                    # sedlex_bench.ml
    yojson/                    # ydump_repeat.ml + sample.json
    zarith/                    # zarith_pi.ml
    owl/                       # owl_gc.ml
    pplacer/                   # pplacer test suite wrapper
    dune-bootstrap/            # dune self-hosting bootstrap
    liquidsoap-lang/           # liq_bench.ml (parser+typechecker)
    js_of_ocaml/               # (parked)

  scripts/
    setup-monorepo.sh          # full setup: pull + patch + build
    vendor-cpdf.sh             # manual vendor for cpdf/camlpdf
    vendor-coq.sh              # manual vendor for zarith
    vendor-devkit-deps.sh      # manual vendor for libevent/ocurl
    vendor-pplacer.sh          # manual vendor for pplacer+mcl

  dune-overlays/               # hand-written dune files for non-dune packages
    camlpdf/                   # upstream uses OCamlMakefile
    cpdf-source/               # upstream uses OCamlMakefile
    zarith/                    # upstream uses configure/make
    libevent/                  # upstream uses Makefile
    ocurl/                     # upstream uses autoconf (config.h pre-generated)

  _rocq_prefix/                # (gitignored) local Rocq install for coqc runtime
  duniverse/                   # (gitignored) ~110 vendored packages
  vendor/                      # (gitignored) manually vendored non-dune packages
```

## Build scripts

Each benchmark has `benchmarks/<tool>/<tool>.build.sh`.  Environment
variables from running-ng:

| Variable | Description |
|----------|-------------|
| `RUNNING_OCAML_OUTPUT` | Path where the built binary must go |
| `RUNNING_OCAML_BENCH_DIR` | Benchmark directory |
| `RUNNING_OCAML_RUNTIME_NAME` | Runtime name (e.g. `ocaml-5.4.1`) |

All build scripts sanitize the opam environment (`unset OPAM_SWITCH_PREFIX`
etc.) to prevent cross-runtime `.cmi` contamination.

## Vendored source patches

Applied automatically by `scripts/setup-monorepo.sh`.  Documented here
for reference and for manual application if needed.

| # | Target | What | Why |
|---|--------|------|-----|
| 1 | `duniverse/alt-ergo/.../theories.ml` | Fix ppx_blob paths | ppx_blob resolves from workspace root |
| 2 | `duniverse/alt-ergo/.../text/dune` | Rewrite dune file | Remove public_name/package (vendored exec) |
| 3 | `duniverse/dune_/dune-project` | `3.22` → `3.21`, rm test/ | dune 3.22 features not in installed dune |
| 4 | `duniverse/ppxlib/` | Replace with git main | Adds Ast_506 for OCaml 5.6 trunk |
| 5 | `duniverse/lwt/` | Replace with git main | Fixes socketaddr.h for OCaml 5.6 |
| 6 | `duniverse/devkit/lwt_engines.ml` | Add `engine_id` type + method | lwt 6.1.1 added virtual `id` method |
| 7 | `vendor/libevent/libevent.ml` | Add `~persist`, `~signal` labels | OCaml 5.x strict label matching |
| 8 | `duniverse/js_of_ocaml/.../dune` | Remove public_name | Vendored executable (parked) |
| 9 | `duniverse/ocamlformat/.../dune` | Remove public_name | Vendored executable |
| 10 | `duniverse/owl/.../exponpow.c` | Fix `std_gaussian_rvs` calls | Upstream C bug: function takes no args |
| 11 | `duniverse/batteries-included/.../batGc.mli` | Add `live_stacks_words` field | OCaml 5.6 added field to `Gc.stat` |
| 12 | `vendor/pplacer/mcl/caml/caml_mcl.c` | Add `#include <stdint.h>` | OCaml 5.6 trunk headers need it |

## Known limitations

- **Rocq symlink**: The setup script creates a symlink at
  `<parent_of_monorepo>/install/default/lib/rocq-runtime` pointing at
  `_rocq_prefix/`.  This is needed because dune's generated `.vo` compilation
  rules use relative paths that resolve outside the monorepo.
  `make clean-all` removes this symlink.

- **js_of_ocaml**: Parked.  Needs findlib at runtime to locate `stdlib`
  package.  Also constrained to OCaml < 5.5.

- **melange**: Parked.  Requires `(using melange 0.1)` dune extension to
  compile OCaml→JS; can't benchmark standalone.

- **Frama-C**: Parked.  EVA analysis plugin doesn't build as a `.cmxs`
  in the vendored context due to dune-site plugin loading limitations.

- **OxCaml**: Only menhir and dune-bootstrap work.  Other tools fail due
  to locality type annotation errors in vendored ecosystem packages.

- **Trunk (5.6) support**: Depends on ppxlib and lwt git main branches
  (patches 4 + 5).  When ppxlib releases a 5.6-compatible version, these
  patches can be removed and the lock file updated.

- **pplacer**: Vendored manually (not in opam).  Requires `libgsl-dev`
  and `libsqlite3-dev` system packages.

## Updating dependencies

```bash
# 1. Modify dune-project if adding/removing packages
# 2. Re-lock
OPAMSWITCH=running-ng-tools opam monorepo lock
# 3. Rebuild from scratch
make clean-all
make setup
# 4. Commit the updated lock file
git add macro-benches.opam.locked dune-project *.opam
git commit -m "Update vendored dependencies"
```

## Adding a new benchmark

1. Add a `(package ...)` declaration in `dune-project`
2. Create an `.opam.template` if non-dune deps need `x-opam-monorepo-opam-provided`
3. Re-lock: `opam monorepo lock`
4. Create `benchmarks/<tool>/` with:
   - `<tool>.build.sh` — build script (see existing ones for template)
   - `dune` — if the benchmark is custom `.ml` code compiled in the workspace
   - Input files (`.mly`, `.smt2`, `.json`, etc.)
5. Add to `running-ng/src/running/config/macrobenchmarks_monorepo.yml`
6. Add to the test build list in `scripts/setup-monorepo.sh`
7. Test: `make clean-all && make setup`
