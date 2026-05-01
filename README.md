# macro-benches

DaCapo-style OCaml macrobenchmark suite for cross-runtime comparison.
All benchmark tool sources and dependencies are vendored via
[opam-monorepo](https://github.com/tarides/opam-monorepo), ensuring
**identical source code** across all runtimes.  The only variable is
the compiler.

## Benchmarks

18 active tools, 28 benchmark programs, 16 categories.  Target runtime:
5-20s per benchmark (DaCapo sweet spot).

| Benchmark | Category | Programs | ~Runtime | Notes |
|-----------|----------|----------|----------|-------|
| **menhir** | Text processing | 3 (ocamly, sql, sysver) | 3-33s | ocamly uses `--canonical` |
| **cpdf** | Text/media | 4 (merge, blacktext, scale, squeeze) | 5-36s | |
| **alt-ergo** | SMT solver | 3 (fill, yyll, unsat_smt2) | 14-19s | fill uses `fill_x100.why` |
| **coq/rocq** | Proof assistant | 1 (corelib_stress) | 52s | fib, ack, tree construction; 1.1GB RSS |
| **ahrefs-devkit** | GC stress | 4 (htmlstream, stre, network, gzip) | 10-25s | in-process iter loop |
| **irmin** | Databases | 1 (mem_rw) | 12s | |
| **ocamlformat** | Build tools | 1 (format 16k-line file) | 5s | |
| **decompress** | Compression | 1 (zlib compress/decompress) | 5s | |
| **eio** | Concurrency | 1 (fiber stream 60M items) | 6s | OCaml ≥ 5.2 |
| **sedlex** | Text processing | 1 (tokenize 700k lines) | 5.5s | |
| **yojson** | Data formats | 1 (parse+serialize 1000x) | 5.5s | |
| **zarith** | Numerics | 1 (15000 digits of pi) | 7s | |
| **owl** | ML/Numerics | 1 (matrix/graph computation) | 16s | OpenBLAS, in-process iter loop |
| **pplacer** | Bioinformatics | 1 (224-test phylogenetic suite) | 17s | GSL, sqlite3, env-var iter loop |
| **dune-bootstrap** | Build tools | 1 (bootstrap dune from source) | 55s | end-to-end; subprocess-bound |
| **ocamlc-self-compile** | Build tools | 1 (`ocamlc` on 400k-line workload) | 8.6s | single-process; closes Ephemeron + Marshal gaps |
| **liquidsoap-lang** | DSL compiler | 1 (parse+typecheck 50k iterations) | 26s | Jane Street PPX (≥ 5.3) |
| **liq-video-frames** | GC pacer / off-heap | 1 (10k 1280×720 Bigarray frames) | 20s | Probes [#13123](https://github.com/ocaml/ocaml/issues/13123) — RSS-focused |
| **js_of_ocaml** | Compilers | — (parked) | — | findlib runtime dep + ocaml < 5.5 |

### Runtime compatibility

| Runtime | Working benchmarks |
|---------|-------------------|
| **OCaml 5.4.1** | All 18 active tools (28 programs) |
| **OCaml trunk (5.6)** | All 18 active tools — ppxlib+lwt upgraded from git |
| **OxCaml** | menhir (3), dune-bootstrap, test_decompress, zarith_pi (6 programs) |
| **OCaml 5.4.1 ± fp ± flambda** | All 18 active tools (used by `fp_flambda_macrobenchmarks.yml`) |

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
    ocamlc-self-compile/       # ocamlc on 400k-line generated workload
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

## Benchmark characteristics

What each benchmark exercises in the OCaml runtime, what its
allocation profile looks like in practice, and what kinds of runtime
change would most likely show up as a regression on it. Use this to
narrow down a regression: if `eio_fiber_stream` moves but
`coqc_corelib_stress` doesn't, the change is unlikely to be in the
minor-GC fast path (which `coqc` would catch) and more likely in the
effect handler / fiber scheduler.

### Allocation profiles — shorthand

These tags appear throughout. They reflect the *measured* dataset
profile (`obelisk-2026-04-21` baseline, post-calibration).

- **minor-saturation** — almost all wall time in minor GC; tiny live set.  
  *Sensitive to:* minor heap size (`s=`), allocation fast path, frame pointers (`-fp`).
- **promotion-heavy** — high fraction of allocations survive the minor heap (`promoted_pct ≥ 10%`, often `major_collections / minor_collections ≥ 25%`).  
  *Sensitive to:* minor-to-major copy, major-heap pacing (`o=`), mark/sweep latency.
- **major-heavy / sustained working set** — large live set across iterations.  
  *Sensitive to:* major-GC algorithm, compaction.
- **off-heap (Bigarray / Bigstring / GMP)** — bulk data outside the OCaml heap.  
  *Sensitive to:* FFI overhead, finalisation, stub-call cost.
- **compute-bound** — < 5% GC overhead; numbers move with codegen quality, not GC.  
  *Sensitive to:* flambda passes, prefetch, register allocation, branch prediction.
- **subprocess-bound** — wall time = waiting on child processes; parent runtime is idle.  
  *Sensitive to:* compiler binary perf, file I/O. Olly observability is meaningless.

---

### Compiler throughput / external work

#### `dune_bootstrap` — `ocaml boot/bootstrap.ml`

**What it does.** Reads `boot/bootstrap.ml` in the dune monorepo, which uses `Sys.command` to drive several `ocamlc` invocations and finally `exec`s the resulting `.duneboot.exe` (which then compiles dune itself in another OCaml process). Wall time is the end-to-end bootstrap of dune from source.

**Profile.** subprocess-bound. The parent ocaml process we measure does almost nothing — 11 minor / 5 major collections in 55s. `gc_overhead = 0.0%` is correct but uninformative.

**Diagnostic value.** Wall time is a real-world compiler-throughput metric (~100 KLOC compile). Regression here without movement on any other benchmark almost certainly means **`ocamlc` codegen, link, or startup got slower** — runtime changes won't move it. Conversely, it's blind to allocation-path changes (it'll happily report "no regression" while the runtime regressed, because the parent doesn't allocate).

#### `ocamlc_self_compile` — variant's own ocamlc on a generated workload

**What it does.** Concatenates the 20 classic OCaml-testsuite benchmark files (boyer, nucleic, raytrace, kb, fft, fannkuch_redux, …) from `js_of_ocaml/benchmarks/sources/ml/`, wraps each in a unique module, and replicates the whole set 30× — generating ~400 k lines of real, compiler-stress OCaml code. Then invokes the **variant's own `ocamlc`** (bytecode compiler — *not* `ocamlopt`) on that file. Single observable OCaml process.

**Profile.** wall ≈ 8.6s on `5.4.1/baseline`, gc_overhead 33%, **4384 minor / 16 major collections, 1.0 GB RSS, promoted_pct 12.5%**. Cross-variant spread is small (8.3–10.0s, ~20%) because the workload is uniform.

**OCaml features.**
- **Ephemeron tables** in `typing/btype.ml` — used for type hash-consing. This is the canonical real-world ephemeron workload.
- **Hashtbl** at scale — environment lookups, scope tables, term-hashing.
- **AST allocation** — `Parsetree.structure` blocks per top-level item; lots of small `Location.loc` wrappers.
- **`Format` module** for diagnostic printing (lazily — most warnings don't fire).
- **`Marshal`** — every successful compilation writes a `.cmi` (the typed signature). The serialised structure includes hashed type names.
- **Polymorphic `compare` on AST nodes** (used by some passes for canonicalisation).

**Why `ocamlc` (bytecode) and not `ocamlopt` (native).** With `ocamlopt`, flambda variants run *additional* compiler passes (the flambda IR optimisation pipeline) — so cross-variant deltas conflate "runtime perf" with "flambda does extra work". With `ocamlc`, the same pipeline runs everywhere, so cross-variant deltas reflect runtime performance only. (In our 4× 5.4.1 measurement: ocamlc spread is 1.39–1.51s, ≈ 8%; ocamlopt spread is 3.09–6.41s, ≈ 2×.)

**Diagnostic value.** Strongest single signal in the suite for:
- **Ephemeron** code paths (`caml_ephe_*`).
- **Marshal** serialisation.
- **Hashtbl** scaling under realistic key/value sizes.

Pairs with `liq_parse_typecheck` (also AST-shaped). Movement on ocamlc_self_compile but not liq → likely Ephemeron or Marshal specifically. Movement on both → general AST-allocation path. Movement on `coqc_corelib_stress` *and* `ocamlc_self_compile` → minor-allocator fast path.

Complements `dune_bootstrap`: that one measures end-to-end compiler experience as users feel it (with subprocess overhead and all); this one isolates compiler internals in a single observable process.

---

### OCaml 5 effects / fiber scheduling

#### `eio_fiber_stream` — Eio.Stream producer/consumer

**What it does.** Spawns 4 producer fibers and 4 consumer fibers. Each producer pushes 15 million tuples `(int, int, String.make 64 c)` onto a bounded `Eio.Stream` (capacity 1024); each consumer pops them. Total: 60 M items, ≈ 3.6 GB of fresh 64-byte strings allocated and discarded. Single domain.

**Profile.** Promotion-heavy: 5145 minor / 1386 major (~27% major:minor); promoted_pct ≈ 10%. Wall ≈ 6s. The fiber-yield pattern around the bounded stream means each push/pop touches the scheduler.

**OCaml features.**
- **Effects** (OCaml 5 only). Eio's primitives — `Eio.Stream.add`/`take`, `Eio.Fiber.both`/`all`, `Eio_main.run` — are implemented with `Effect.perform` and deep `try_with` handlers. The benchmark exercises them indirectly but at high volume.
- **Fiber stack** allocation/reuse — each `Fiber.both` creates two fiber stacks; fast scheduler depends on stack-pool reuse.
- **Atomic operations** for the stream's bounded queue.

**Diagnostic value.** This is the *only* benchmark in the suite that would move on:
- Effect-handler internals (`runtime/runtime_effects.c`, deep_try_with implementation).
- Fiber stack allocator changes.
- Eio's scheduler internals (which depend on `Atomic`).

Regression here without correlated movement on any allocation-heavy benchmark (`coqc`, `liq`, `sedlex`) → suspect effects/fibers. Movement on this *and* every promotion-heavy bench → suspect minor-to-major copy path. Won't run on OCaml < 5.2.

---

### GC stress — minor-saturation

#### `coqc_corelib_stress` — Coq kernel reduction on unary `nat`

**What it does.** Type-checks `coq_corelib_stress.v`, which forces the Coq kernel to reduce four expressions: `fib 23`, `sum_to 1000`, `ack 3 8`, `tree_size (make_tree 13)`. All operate on Coq's unary-Peano `nat` representation (`O | S nat`) — every `S` constructor is an allocation.

**Profile.** Minor-saturation at extreme: ~94% gc_overhead is **constitutional**, not pathological. ~6 k minor / 8 major collections per ~52s wall on this machine. Mutator time is single-digit seconds; the rest is GC. Tested on shrunk inputs (the original `fib 25, ack 3 10, ...` pushed wall to 715s and 4.4 GB RSS — same character, just bigger).

**OCaml features.**
- **Minor-GC fast path** — heap-pointer bump for every `S`.
- **Constructor allocation** — every reduction step allocates one block.
- **Match compilation** — kernel reduction is essentially a `match` interpreter over `nat`.
- Major GC barely engaged (the live set is small even though throughput is huge).

**Diagnostic value.** This is the canonical *minor-allocator-stress* benchmark. If it regresses but allocation-light benchmarks don't, the problem is in:
- The minor-allocator fast path (`caml_alloc_small`-equivalent).
- Constructor block initialisation.
- The young-pointer write barrier.

Conversely, it's *insensitive* to major-GC changes (almost no major work happens). A change that fixes a major-GC bug shouldn't move `coqc` at all — if it does, suspect a side-effect.

#### `menhir_ocamly` — canonical LR(1) on the OCaml grammar

**What it does.** Menhir constructs the **canonical** LR(1) automaton (not LALR) for `ocaml.mly` (3006 lines). Canonical LR(1) keeps every distinct `(state, lookahead)` pair instead of merging them — the state table is enormous for OCaml's grammar.

**Profile.** Wall ≈ 33s, gc_overhead ≈ 20%, **RSS ≈ 2.7 GB** — the state table is genuinely that large. ~17 k minor / 27 major collections (minor-saturation pattern; the 2.7 GB lives across the whole run).

**OCaml features.**
- **Hashtbl** at scale (state-keyed lookups).
- **Polymorphic `compare`** (used by `Set.Make` and Hashtbl on structured keys).
- **Large-array allocation** for the state table.
- AST/IR allocation for the grammar.

**Diagnostic value.** Sensitive to large-table generation perf and `compare` codegen. The other two menhir benchmarks (`sql_parser`, `sysver`) test smaller scales of similar work — co-movement across all three menhir benchmarks isolates "menhir-specific" issues from "OCaml-specific" issues.

---

### GC stress — promotion-heavy

#### `liq_parse_typecheck` — Liquidsoap parser + typechecker

**What it does.** Parses + typechecks the same ~80-line Liquidsoap script `iterations` times (default 50000). Each iteration constructs a fresh AST, then `Liquidsoap_lang.Runtime.type_term` traverses it doing type inference.

**Profile.** **Extreme promotion**: 26 k minor / **12.7 k major** collections (≈ 48 % major:minor — among the highest in the suite). gc_overhead ≈ 22%, wall ≈ 26s. Each AST is built fresh, immediately type-checked while it's still alive, then drops out of scope.

**OCaml features.**
- **AST as recursive variants** — heavy small-block allocation.
- **Closures & first-class functions** — Liquidsoap's runtime has `fun (x) -> ...`-style values.
- **Mutation-during-inference** — typechecker uses unification (`ref` cells in type variables).
- **Jane Street ppxlib** (build-time PPX). Affects only build, not runtime.

**Diagnostic value.** AST-with-type-inference is a *very common* OCaml workload pattern (compiler tooling, DSLs, language servers). Movement here without movement on `ocamlformat_rocq` (similar shape) → suspect liquidsoap-specific. Movement on both → suspect AST allocation patterns or `Hashtbl` perf. Heavy promotion makes it specifically sensitive to **minor-to-major copy** code paths.

#### `ydump_repeat` — yojson parse + serialize

**What it does.** Reads a 670 KB JSON file and 1000× parses it (`Yojson.Safe.from_string`) then serialises it back (`Yojson.Safe.to_string`). The parsed AST is the recursive variant `[ \`Assoc of (string * t) list | \`List of t list | ... ]`.

**Profile.** ≈ 5.5s, gc_overhead 4.5%, but **65 % major:minor ratio** (1654 major / 2541 minor) — every iteration's AST persists long enough to promote.

**OCaml features.**
- **Recursive polymorphic variants** — variants are blocks; deep nesting means deep promotion chains.
- **String allocation** for keys and string-typed values.
- **In_channel / String I/O** (only at startup; per-iteration cost is parse+serialise).

**Diagnostic value.** Recursive variant + promotion is the JSON-shaped workload. Pairs naturally with `liq_parse_typecheck` (also AST-shaped). Movement together → AST/promotion path. Movement here only → yojson-specific.

#### `test_decompress` — pure-OCaml zlib

**What it does.** Decompresses 32 KB of compressed data 64 times using the `Decompress` library (no C — pure OCaml zlib implementation built on `Bigstring` buffers).

**Profile.** Wall ≈ 5s, gc_overhead 2.4% — looks compute-bound at first glance, but the major:minor ratio is 50% (1379 / 2731). The Bigstring buffers are reused across iterations (allocated once), but the per-chunk decompression state (small blocks) gets promoted each round.

**OCaml features.**
- **Bigstring** (`Bigstringaf`) — off-heap buffers used for the I/O bigarrays. Their headers live on the OCaml heap.
- **State machines** in pure OCaml — `De.Lz77.make_window`, `De.Queue.create`, etc. — small-block allocation per chunk.

**Diagnostic value.** Movement here without correlated `owl_gc` movement → not a Bigarray problem (since both use Bigarray). Movement on both → Bigarray finalisation or stub overhead. Movement here without movement on `liq` → not promotion in general; suspect Bigstring header allocation specifically.

#### `pplacer_testsuite` — phylogenetic OUnit tests

**What it does.** Runs 224 OUnit tests through the pplacer phylogenetics library `N` times in-process via `PPLACER_TEST_LOOP`. Tests construct phylogenetic trees, run statistical/numerical computations through `gsl`, and persist intermediate state via sqlite3.

**Profile.** Wall ≈ 13s at arg=5, gc_overhead 70% (in the upper tier), 70 MB RSS. Allocation pattern: 1985 minor / 712 major per iteration (≈ 36 % major:minor — heavy promotion).

**OCaml features.**
- **gsl** bindings (numerical — exp_priors, gaussian, etc., done in C).
- **sqlite3** bindings (in-memory for tests).
- **Tree/node allocation** in pure OCaml — phylogenetic trees are recursive types.
- **Polymorphic `compare`** on tree-structured data (lots of testing).

**Diagnostic value.** Mix of FFI + tree-allocation. Co-movement with `owl_gc` → FFI or numerical-codegen path. Co-movement with `liq` (but not `owl_gc`) → tree/AST allocation. Sole movement → suspect gsl or sqlite3 wrapper specifically.

---

### FFI / off-heap memory

#### `owl_gc` — Bigarray Gromov-Wasserstein distances

**What it does.** Generates 100 random 100×100 `Bigarray.Array2` matrices, then for each (i, j) pair computes `Gw.gw_uniform a_i a_j` — a frobenius-product / matrix-multiply cascade over the OCaml `Owl.Mat` API (which dispatches to OpenBLAS via C). 5000 pair calls per iteration.

**Profile.** Wall ≈ 16s at arg=6 (`re-25` ring), gc_overhead **50%**, RSS 151 MB. Striking: `minor_collections == major_collections` (62970 each per 6 iterations) — every minor collection accompanies a major step. That's a Bigarray-finalisation-driven pattern: each `Mat.dot` allocates a bigarray header on the OCaml heap whose finaliser frees the off-heap data.

**OCaml features.**
- **Bigarray** (`Array2`, `Genarray`) — bulk float data lives off the OCaml heap; a small block on the heap holds the header + finaliser.
- **Custom-block finalisation** — Bigarray's `finalize` callback is what releases the off-heap memory.
- **OpenBLAS** stub calls per `Mat.dot` (matrix multiply), `contract2` (Frobenius product). C call overhead per call.
- **No closures of note** — straight imperative loops over int indices.

**Diagnostic value.** This is the *Bigarray-and-FFI* canary. If it regresses but `coqc_corelib_stress` doesn't, the runtime's allocation fast path is fine — suspect:
- Bigarray finaliser performance (we're allocating thousands of finalised blocks per second).
- Stub-call overhead — OpenBLAS calls happen in the inner loop.
- `Custom_operations` table dispatch.
- Owl's wrapper layer between OCaml and BLAS.

#### `zarith_pi` — π via spigot algorithm with GMP

**What it does.** Streaming spigot algorithm (Gibbons 2004) computing `Z.t` arbitrary-precision π to 15000 digits. Every arithmetic operation (`+ * /`) creates a new `Z.t` (a custom block with a GMP `mpz_t` inside).

**Profile.** Wall ≈ 8s, gc_overhead 27%, but extraordinary collection counts: **102 k minor / 66 k major** — by far the highest in the suite. The mass of small `Z.t` allocations comes from GMP boxing/unboxing.

**OCaml features.**
- **Zarith / GMP** stub calls — every `Z.add`, `Z.mul`, etc. is a stub call into libgmp.
- **Custom blocks** — `Z.t` is a custom block with GMP-aware finaliser, comparison, hash, marshal/unmarshal callbacks.
- **Tail recursion** — the algorithm is structured as `digit k z n row col` recursion.

**Diagnostic value.** Sensitive to:
- Custom-block allocation/finalisation overhead — the *fastest-allocating* benchmark in the suite, all custom blocks.
- GMP stub-call overhead.
- Tail-call optimisation (every `digit` call is in tail position).

Movement here without corresponding `owl_gc` movement → suspect custom-block path specifically (`zarith` uses them, `owl_gc` uses Bigarray). Movement on both → general FFI overhead.

#### `liq_video_frames` — synthetic large-Bigarray streaming (heap-growth probe)

**What it does.** Allocates 1280×720 RGBA8 video frames as `Bigarray.Array1 Char` (~3.5 MiB each, off-heap with a finaliser) in a tight loop, fills each frame via `Bigarray.Array1.fill` (`memset`-equivalent — commits all pages to RSS), then discards. A persistent ~320 MiB `int array` "deadweight" simulates liquidsoap's loaded standard library + script state. arg=10000 → ~20s wall on obelisk; toggle `LIQ_NO_DEADWEIGHT=1` to disable the deadweight (~10 MB RSS, control case).

**Profile.** Wall ≈ 20s, gc_overhead modest (each frame is large enough to bypass minor-heap promotion and go straight to major), but **RSS varies ~34% with `space_overhead`**: `o=40` → 458 MB, `o=80` → 499 MB, `o=120` (default) → 534 MB, `o=200` → 612 MB. The OCaml heap stays small but RSS reflects how much off-heap budget the GC pacer keeps live.

**OCaml features.**
- **Bigarray** of `Char` — large-allocation custom block path (different code path from `owl_gc`'s small-matrix Bigarrays, which go through minor-heap promotion).
- **Off-heap memory accounting** in the major-heap pacer — `caml_alloc_custom_mem` reports the off-heap size to the GC, which factors it into space_overhead decisions.
- **Persistent live data** (the deadweight) interacting with `space_overhead` to control major-heap headroom.

**Diagnostic value.** This is a focused probe of the pattern in [ocaml/ocaml#13123](https://github.com/ocaml/ocaml/issues/13123) — the regression liquidsoap reported when moving from 4.14 to 5.x, and the workload Romain Beauxis describes in [the ai-radio blog post](https://www.liquidsoap.info/blog/2024-02-10-video-canvas-and-ai/) ("a short term streaming loop allocating a lot of custom blocks with large external memory"). The headline signal is **`max_rss_kb`**, not wall time. What to look for:
- **`o=40` vs default RSS gap**: replicates the issue's `space_overhead=40` workaround. If the gap shrinks across releases, the pacer is becoming more conservative by default (fix). If the gap grows, the regression is widening.
- **No movement on this benchmark + movement on `owl_gc`** → the small-Bigarray (minor-heap-promoted) pacer code path has changed but the large-Bigarray (direct-major) path hasn't. We saw exactly this pattern on 5.4.1 → d8bb46c (5.5-beta): `owl_gc` improved 27%, this benchmark's RSS was unchanged.
- **Movement here** → the `caml_alloc_custom_mem` accounting or `space_overhead` policy itself changed.

The benchmark is *not* a wall-time benchmark — for cross-version regression detection on this workload, compare RSS first. Wall-time differences below ~5% are likely DRAM-bandwidth noise from the `memset` rather than runtime perf.

#### `devkit_gzip` — zlib via C bindings

**What it does.** 8 sub-benches around `Gzip_io` (zlib via Devkit's C bindings): small-buffer compression storms, large-block compression, streaming patterns, header processing.

**Profile.** **Compute-bound** — gc_overhead 1%, wall ≈ 10s, RSS 18 MB. Despite being labelled "GC stress" in the source, the actual GC pressure is minimal because zlib does the work in C with reused `Bytes` buffers.

**OCaml features.**
- **zlib C bindings** (via the `Devkit.Gzip_io` module).
- **`IO.input_string` / `IO.output_string`** wrappers from extlib — the stub interface lives here.
- **`Bytes` buffer reuse** — the source explicitly recycles buffers to avoid allocation churn.

**Diagnostic value.** GC changes shouldn't move this. Compiler-codegen changes (flambda especially) might — the inner loops of bench bodies are tight `for i = 1 to N do ... done` over `Bytes` mutation, which is exactly the kind of code flambda optimises. Movement here → suspect codegen / FFI. The 47% wall regression we observed in earlier datasets between OCaml versions on this benchmark is therefore a *real compute regression* in the new compiler, not GC.

---

### String / Buffer allocation

#### `sedlex_tokenize` — Unicode lexer on generated input

**What it does.** Generates a 700 000-line pseudo-code string in memory (≈ 50 MB), then runs a Sedlex DFA tokeniser over it producing a token list. Sedlex's regex declarations are PPX-expanded into a state-table-driven match.

**Profile.** Wall ≈ 5s, gc_overhead 40%, 2554 minor / 10 major. High minor pressure but virtually no major work — the token list is the only persistent state and even that is short-lived.

**OCaml features.**
- **PPX-generated DFA** — Sedlex emits a giant nested `match` expression / lookup table.
- **`String` allocation** — every `IDENT _` / `NUMBER _` / `STRING _` token wraps a substring of the input.
- **`Sedlexing.Utf8.from_string`** wrapper — UTF-8 decoding logic.
- **`List.length` / `List.iter`** at the end — single linear pass.

**Diagnostic value.** Sensitive to:
- `String.sub` / sub-string allocation cost.
- `match`-compilation perf for DFA-shaped match expressions.
- PPX-emitted code patterns.

Pairs with `devkit_stre` (also string-heavy) — co-movement points at the string allocator; sole movement points at PPX-emitted DFA shape.

#### `devkit_stre` — string operations stress

**What it does.** 8 sub-benches over `Devkit.Stre` (string utilities): split storm with `nsplitc`, substring slicing with `Stre.slice`, pattern operations on multi-line text with email/phone regex-style processing, concatenation chains with `^`, enum-based string ops via `ExtList.Enum`, mixed-size allocations into a `Hashtbl`, buffered string building, transformation chains with sliced rebuilds.

**Profile.** Wall ≈ 14s, gc_overhead 5.5%. `7744 minor / 3012 major` — a notable major:minor ratio (~39%), though the sub-benches explicitly retain prefixes of their `retained_*` lists modulo prime numbers to stress generational behaviour.

**OCaml features.**
- **`String.sub`, `String.concat`, `String.uppercase_ascii`** — the OCaml stdlib paths.
- **`Stre.nsplitc`, `Stre.slice`, `Stre.from_to`** — Devkit's string library.
- **`Hashtbl`** with int and string keys (in `bench_mixed_size_allocations` and `bench_transformation_chains`).
- **`ExtList.Enum`** — lazy enumerations from extlib.

**Diagnostic value.** Generational pressure with intentional retention. Movement here with no movement on `coqc` → suspect minor-to-major *promotion path* (rather than minor allocation). Movement with `sedlex_tokenize` → string-allocation path generally.

#### `ocamlformat_rocq` — formatting a 16k-line Rocq file

**What it does.** Runs `ocamlformat --impl workload_5x.ml -o /dev/null` on a 663 KB / 16 610-line OCaml file (extracted from the Rocq prover source). Parses to AST, runs OCamlformat's pretty-printing pipeline, writes formatted output.

**Profile.** Wall ≈ 5s, gc_overhead 30%, 2906 minor / 22 major. Minor-heavy with light promotion — most allocation is short-lived `Format` boxes.

**OCaml features.**
- **`Format` module** — `pp_*` printers, `box`, `hov`, `cut`. Heavy `String.concat` / `Buffer.add_*`.
- **OCaml AST** (`Parsetree.structure`) construction during parsing.
- **OCamlformat's "AST_transform" passes** — multiple AST traversals (normalising, attribute handling, etc.).

**Diagnostic value.** Co-moves with `liq_parse_typecheck` (both AST-shaped) and with `sedlex_tokenize` (both heavy `Buffer`/`Format` users). Movement here alone → OCamlformat-specific (its Ast_transform pipeline).

#### `cpdf_*` — PDF manipulation (4 variants)

**What they do.** Each invokes `cpdf` (CamlPDF wrapper) on a 32 MB reference PDF (`PDFReference16.pdf_toobig`). Variants:
- **`cpdf_merge`** — merges the PDF with itself, output to `/dev/null`.
- **`cpdf_blacktext`** — converts all text to black.
- **`cpdf_scale`** — scales pages to A4 landscape and 2-up layout.
- **`cpdf_squeeze`** — re-compresses object streams.

**Profile.** Walls vary: merge 5.6s, blacktext 6.8s, squeeze 9.1s, scale 35.7s. All medium gc_overhead (20–40%), low minor-collection counts (~1k–9k), low major (~30–50). I/O matters — the 32 MB input is read at startup.

**OCaml features.**
- **CamlPDF / cpdf-source** — both vendored from upstream OCamlMakefile-based packages (overlaid with hand-written dune files; see Patches §). Pure OCaml, no FFI.
- **`Bytes` mutation** — cpdf manipulates byte-level PDF objects.
- **File I/O** at startup (the `pdf_toobig` is genuinely too big — reading it is non-trivial).

**Diagnostic value.** Pure-OCaml byte-level processing. Movement here without movement on Bigarray-using benchmarks → not FFI; suspect `Bytes` allocation/mutation paths or `compare`/match codegen for PDF object types. `cpdf_scale` is conspicuously longer than the other three (35s vs 5–9s) — its workload is genuinely more compute-heavy (page geometry transformation).

---

### I/O and persistent data

#### `irmin_mem_rw` — Lwt + Irmin in-memory KV store

**What it does.** Creates an Irmin in-memory store, then runs three phases: write 3000 keys → read all 3000 keys → 20000 mixed read/write ops with 80% read. Each value is a 100-byte string; each commit creates a new tree node (Irmin is a Git-like persistent store).

**Profile.** Wall ≈ 12s, gc_overhead 11%, 6840 minor / 136 major. Moderate everywhere.

**OCaml features.**
- **Lwt** (`Lwt.bind`, `Lwt_main.run`, `Lwt.return`) — cooperative threading via promises. Every store op returns `'a Lwt.t`.
- **Persistent immutable hash-tree** — Irmin's storage. Every `set` creates a new tree along the path.
- **Hashtbl-style operations** internally on string keys.
- **`Unix.gettimeofday`** for commit timestamps.

**Diagnostic value.** This is the one Lwt benchmark. Co-movement with `eio_fiber_stream` → suspect general scheduler / continuation perf. Movement on this *not* on eio → Lwt-specific (likely `Lwt.bind` codegen). Pairs with `liq_parse_typecheck` only via the persistent-data-structure angle.

#### `devkit_htmlstream` — HTML stream parsing

**What it does.** Generates large HTML inputs (1–5 MB each) into a `Buffer` then parses with `HtmlStream.parse` (Devkit's streaming HTML parser). Multiple sub-benchmarks: small text storm, attribute-list pressure, large block allocations, malformed-tag handling, etc. Some retain a prime-number-modulo subset of parsed text in a list (multi-generational retention).

**Profile.** Wall ≈ 25s, gc_overhead 3.3%, 3537 minor / 150 major.

**OCaml features.**
- **`Buffer.add_string` / `Buffer.contents`** — heavy buffered HTML construction.
- **`HtmlStream` parser** state machine.
- **Multi-generational retention pattern** — `if !counter mod 7 = 0 || ...` retain semantics push some allocations into the major heap.

**Diagnostic value.** Pairs with `sedlex_tokenize` (both Buffer-heavy). Movement here without `sedlex_tokenize` → HtmlStream-specific. Movement together → Buffer allocator.

#### `devkit_network` — IPv4 / CIDR parsing

**What it does.** 8 sub-benches over `Devkit.Network`: IPv4 address parsing (10 000 IPs per pass, ragel-based parser internally), CIDR calculations with bitwise ops, range operations, mixed-format parsing, NAT-table operations on a `Hashtbl`, IP sorting, broadcast calculations, complex network ops with CIDR matching.

**Profile.** Wall ≈ 17s, gc_overhead 4.5%, 10 409 minor / 74 major. Minor-heavy, almost no promotion.

**OCaml features.**
- **`Devkit.Network`** — ragel-generated IPv4/CIDR parser (the comments mention this).
- **Int32 boxing** — IPv4 addresses are 32-bit; OCaml boxes int32 unless on a 64-bit platform with the value fitting in `int`.
- **`Hashtbl`** for the NAT-table sub-bench.
- **`compare` / `<`** on packed integers (for sorting).

**Diagnostic value.** Movement here is a signal for `Int32` / boxed-int handling, `compare` codegen on small integers, or hashtable perf. Doesn't have FFI (the Network library is pure OCaml).

#### `alt_ergo_yyll` and `alt_ergo_unsat_smt2`

**What they do.** Both run alt-ergo on `.why` / `.smt2` problems: yyll.why (larger native input), unsat.smt2 (Dolmen frontend, with `--timelimit 15`).

**Profile.** yyll: ~19s wall, 6.4% gc_overhead, 7509 minor / 18 major. unsat_smt2: ~15s wall, 7.4% gc_overhead, 12 428 minor / 42 major. Both compute-bound on the SMT theory backend.

**OCaml features.**
- **Native `.why` parser frontend** (yyll) vs **Dolmen `.smt2` frontend** (unsat).
- **Theory backends** — DPLL+T, congruence-closure, integer arithmetic, bitvector — most of the work is here.
- **`Hashtbl`** at scale for term-hashing.

**Diagnostic value.** Three alt-ergo benchmarks (`fill`, `yyll`, `unsat_smt2`) that all move together → suspect alt-ergo's theory backends. Movement on only `unsat_smt2` → Dolmen frontend. Movement on `fill` and `yyll` but not `unsat_smt2` → native frontend.

#### `menhir_sql_parser` and `menhir_sysver`

**What they do.** Generate parsers from `sql-parser.mly` (5846 lines, with `keywords.mly`, `--base sql-parser`) and `sysver.mly` (12 735 lines, `--table` table-driven LR(1)).

**Profile.** sql_parser: ~3.3s, gc_overhead 29%, smaller scale. sysver: ~20s, gc_overhead 33%, 8854 minor / 50 major. Both medium, minor-heavy.

**Diagnostic value.** Together with `menhir_ocamly` they form a triple: ocamly uses `--canonical`, sql_parser uses LALR + `-v -t`, sysver uses `--table`. Movement on all three → menhir-internal regression. Movement on a subset → algorithm-specific. Sysver's larger scale (12k-line grammar) most stresses Hashtbl growth.

---

### Quick-reference cross-table

| Benchmark | wall (s) | gc% | Allocation profile | Strongest signal for |
|---|---|---|---|---|
| `coqc_corelib_stress` | 52 | 94 | minor-saturation | minor-GC fast path |
| `eio_fiber_stream` | 6 | 10 | promotion-heavy | OCaml 5 effects, fiber scheduler |
| `irmin_mem_rw` | 12 | 11 | medium | Lwt, persistent hash-tree |
| `liq_parse_typecheck` | 26 | 22 | promotion-heavy (48%) | AST + minor-to-major copy |
| `ydump_repeat` | 5.5 | 4.5 | promotion-heavy (65%) | recursive variants, JSON tree |
| `test_decompress` | 5 | 2.4 | promotion-heavy + Bigstring | Bigstring header allocation |
| `pplacer_testsuite` | 13 | 70 | major-heavy (FFI) | gsl/sqlite3, tree allocation |
| `owl_gc` | 16 | 50 | off-heap (Bigarray, small) | Bigarray finalisation, OpenBLAS stubs |
| `zarith_pi` | 8 | 27 | off-heap (GMP custom blocks) | custom-block path, GMP stubs |
| `liq_video_frames` | 20 | low | off-heap (Bigarray, large) | space_overhead pacer, RSS growth ([#13123](https://github.com/ocaml/ocaml/issues/13123)) |
| `devkit_gzip` | 10 | 1 | compute-bound | codegen, zlib stubs |
| `devkit_stre` | 14 | 5.5 | minor + retention | string allocator, generational copy |
| `devkit_network` | 17 | 4.5 | minor (Int32) | int32 boxing, Hashtbl |
| `devkit_htmlstream` | 25 | 3.3 | minor + retention | Buffer allocator |
| `sedlex_tokenize` | 5 | 40 | minor-saturation | string allocation, PPX DFA |
| `ocamlformat_rocq` | 5 | 30 | minor + AST | Format module, AST allocation |
| `cpdf_merge` / `_blacktext` / `_squeeze` | 6–9 | 20–40 | minor + Bytes | Bytes mutation, codegen |
| `cpdf_scale` | 36 | 19 | minor (compute) | codegen of geometry transforms |
| `alt_ergo_fill` | 14 | 40 | promotion-medium | SMT theory backends |
| `alt_ergo_yyll` | 19 | 6 | minor (compute) | native frontend, theory backends |
| `alt_ergo_unsat_smt2` | 15 | 7 | minor (compute) | Dolmen frontend, theory backends |
| `menhir_ocamly` | 33 | 20 | minor (canonical LR) | Hashtbl scale, large arrays |
| `menhir_sql_parser` | 3.3 | 29 | minor (LALR + verbose) | menhir internals |
| `menhir_sysver` | 20 | 33 | minor (table) | Hashtbl growth |
| `dune_bootstrap` | 55 | 0 | subprocess-bound | `ocamlc` codegen / link / startup |
| `ocamlc_self_compile` | 8.6 | 33 | minor-heavy + Ephemeron | Ephemeron tables, Marshal (.cmi), Hashtbl, AST allocation |

### Coverage gaps — what NO benchmark exercises

A regression in any of these areas would **not** be caught by the
current suite:

- ~~**`Ephemeron`**~~ — covered by `ocamlc_self_compile` (the OCaml typer's hash-consing tables).
- ~~**`Marshal`**~~ — covered by `ocamlc_self_compile` (`.cmi` writing).
- **`Weak` arrays** — used by hash-consing libraries directly. No benchmark loads or churns a weak-array.
- **Multi-domain parallelism** via `Domainslib` or direct `Domain.spawn`. Eio uses a single domain in our config; nothing distributes work across multiple domains. **No load on inter-domain GC, no domain-local minor heaps under contention.** Phase 2 of the coverage-gaps plan in running-ng (Sandmark imports) would close this.
- **`Gc.alarm` / `Gc.create_alarm`** user callbacks — if the alarm machinery changed, no benchmark would notice.
- **`Gc.compact` interaction with finalisers** — owl_gc has finalisers but never forces compaction.
- **Hot inner-loop float computation** isolating flambda's effect — owl_gc is closest but defers to BLAS, so flambda has nothing to optimise. A pure-OCaml numerical kernel (`Array.iter`, no allocation in the inner loop) would catch flambda regressions cleanly. Phase 2 candidate (raytracer / nbody from Sandmark).
- **`Sys.set_signal` / signal-handler invocation** in tight loops.
- **`Bigarray` slicing and reshape** — owl_gc creates and uses Array2 but doesn't exercise slicing-heavy patterns.
- **Polling-points / safe-point** density — no benchmark stresses the cooperative-cancellation path that depends on poll insertion.

These are candidates for future benchmarks. If a runtime change
touches one of those areas, the current suite won't catch it — flag
the gap explicitly when proposing the change.

## Iteration counts (in-process loops)

A few benchmarks have per-invocation work that's too short to measure
reliably — startup overhead dominates and observability tools (olly,
perf) lose precision.  Two patterns are in use:

**Shell-loop wrapper** (legacy, *broken for olly*).  Some build scripts
generate a wrapper that runs the binary `N` times in a shell loop:

```bash
for _ in $(seq 1 "$ITERATIONS"); do
  "${REAL_EXE}" >/dev/null 2>&1
done
```

This works for wall-time aggregation but **breaks olly's runtime_events
attach model**: olly sees a single OCaml process at a time. With short
per-child work (e.g. `devkit_stre`) the events files may stack in
`/tmp` and olly aggregates them; with longer per-child work
(`pplacer_testsuite` at ~3.5 s/child) olly attaches to the first child
only and reports its lifetime, missing the other N−1 invocations
silently.  Affected benchmarks: `devkit_stre`, `devkit_gzip`,
`devkit_network`, `owl_gc`.

**Env-var in-process loop** (recommended).  The OCaml entry point reads
an env var and runs the work N times inside the same process.  The
wrapper script just sets the env var and `exec`s the binary — no shell
loop:

```ocaml
(* tests.ml *)
let loop = try int_of_string (Sys.getenv "PPLACER_TEST_LOOP") with _ -> 1 in
for _ = 1 to (loop - 1) do
  let _ = run_test_tt suite in ()
done;
run_test_tt_main suite
```

```bash
# pplacer.build.sh wrapper
PPLACER_TEST_LOOP="${1:-1}" exec "${TESTS_EXE}"
```

The YAML's positional arg becomes the loop count; one OCaml process
does N iterations of work; olly observes the full benchmark.

In use by:

| Benchmark | Env var / arg | Notes |
|---|---|---|
| `pplacer_testsuite` | `PPLACER_TEST_LOOP` env var | OUnit test runner; uses env var to avoid clashing with OUnit's own argv parsing |
| `owl_gc` | `Sys.argv.(1)` | Plain OCaml main; argv is unused otherwise |
| `devkit_stre` | `Sys.argv.(1)` | Plain OCaml main; loops the 8 sub-benches (split, slicing, pattern ops, etc.) |
| `devkit_gzip` | `Sys.argv.(1)` | Same shape as stre. gc_overhead ≈ 1% — compute-bound |
| `devkit_network` | `Sys.argv.(1)` | Same shape as stre. ipv4/cidr parsing benchmarks |
| `liq_video_frames` | `Sys.argv.(1)` | Number of frames to allocate. RSS-focused, not wall-time |

**Ring-size interaction.** A single OCaml process accumulating events
across N iterations needs more `runtime_events` ring than N separate
processes (each with their own ring). For allocation-heavy benchmarks
(`owl_gc` in particular), large iteration counts can overflow the
ring and cause olly to report lost events plus a corrupted
`wall_time`. The current convention is `re-25` (32 MB ring) for the
in-process-loop benchmarks; bump to `re-26` (64 MB) or higher if a
new benchmark hits the limit. Empirical sizing table for `owl_gc`:

| arg | wall (s) | overflow at `re-23` (8 MB) | overflow at `re-25` (32 MB) |
|---|---|---|---|
| 1 | 2.6 | no | no |
| 2 | 5.3 | no | no |
| 3 | 7.9 | no | no |
| 4 | 10.6 | no | no |
| 5 | 13.3 | yes — corrupted wall_time | no |
| 6 | 15.8 | yes | no — current setting |

When porting another benchmark to this pattern:

1. Wrap the OCaml entry point with the env-var loop (default 1).
2. If the benchmark CLI is otherwise untouched (e.g. it doesn't take
   any args), `Sys.argv.(1)` is fine instead of an env var.  Use an
   env var when the entry point already parses argv (OUnit, alt-ergo,
   etc.).
3. Update the build script's wrapper to drop the shell `for` loop and
   just `exec` the binary, passing the count through as the env var.
4. Update `running-ng/src/running/config/macrobenchmarks_base.yml`'s
   `args:` to be the loop count rather than an external iteration
   count.
5. Document the new env var in the table above.

If the OCaml entry point is upstream code (vendored from another
project), record the patch in `scripts/setup-monorepo.sh` so it
survives a re-vendor.

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
| 13 | `vendor/pplacer/tests/tests.ml` | Add `PPLACER_TEST_LOOP` env-var loop | Run the test suite N times in one process so olly observes the full benchmark — see §"Iteration counts" |

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
