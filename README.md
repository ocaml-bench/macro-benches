# macro-benches

DaCapo-style OCaml macrobenchmark suite for cross-runtime comparison.
All benchmark tool sources and dependencies are vendored via
[opam-monorepo](https://github.com/tarides/opam-monorepo), ensuring
**identical source code** across all runtimes.  The only variable is
the compiler.

Designed to work two ways:

- **Standalone** — `make setup` once, then build any tool under any
  opam switch (`dune build -- benchmarks/<name>/<name>.exe`) and run
  the resulting binary directly.
- **Orchestrated** — used as the macrobenchmark backend for
  [running-ng](https://github.com/udesou/running-ng), which manages
  per-runtime opam switches and drives cross-runtime / flag / GC-param
  sweeps. See §"Run via running-ng" below.

## Benchmarks

19 active tools, 32 benchmark programs, 18 categories.  Target runtime:
5-25s per benchmark (DaCapo sweet spot; lavyek's 1d cell sits at the upper edge).

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
| **ocamlc-self-compile** | Build tools | 1 (`ocamlc` on 400k-line workload) | 8.6s | single-process; Marshal-heavy (.cmi/.cmo write), Bigarray emit buffer, Hashtbl-scale TypeHash. Does **not** exercise Ephemerons — verified against 5.4.1 and trunk compiler-libs |
| **liquidsoap-lang** | DSL compiler | 1 (parse+typecheck 50k iterations) | 26s | Jane Street PPX (≥ 5.3) |
| **liq-video-frames** | GC pacer / off-heap | 1 (`pool` — refcounted-pool Bigarrays, 30k 1280×720 YUV420 frames) | 4-20s | Probes [#14533](https://github.com/ocaml/ocaml/issues/14533) — 3-plane YUV420 Bigarrays per frame (mm-faithful, POOL=1+TOUCH=full); env knobs `LIQ_POOL`, `LIQ_DW_MB`, `LIQ_CHURN`, `LIQ_PACE_FPS` |
| **merlin** | IDE / domains+effects | 1 (7 cram queries × N) | 16s | merlin-domains branch; **DISABLED — upstream race** |
| **js_of_ocaml** | Compilers | 1 (compile runtime's ocamlc.byte to JS) | 7-9s | jsoo `ocaml-5.6` branch + cmdliner 2.1.0 |
| **lavyek** | Multi-domain KV / Eio + Atomic + io_uring | 4 (kv_1d, kv_2d, kv_4d, kv_8d) | 6-25s | OCaml ≥ 5.2; per-domain CPU pinning via `ocaml-processor`. (Note: imports `kcas`/`kcas_data` in `dune-project` but the in-memory index is actually hand-rolled `Atomic.*` — kcas is unused in source) |

### Runtime compatibility

| Runtime | Working benchmarks |
|---------|-------------------|
| **OCaml 5.4.1** | All 19 active tools (32 programs) |
| **OCaml d8bb46c (5.5-beta)** | All 19 active tools |
| **OCaml trunk (5.6)** | All 19 active tools — ppxlib+lwt upgraded from git |
| **OxCaml** | menhir (3), test_decompress, zarith_pi (5 programs) |
| **OCaml 5.4.1 ± fp ± flambda** | All 19 active tools (used by `fp_flambda_macrobenchmarks.yml`) |
| **OCaml d8bb46c ± fp ± flambda** | All 19 active tools (used by `fp_flambda_macrobenchmarks.yml`) |

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

This runs 9 steps: pulls ~110 vendored packages, applies 13 patches,
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
CONFIG_FILE=src/running/config/experiments/macrobenchmarks_monorepo.yml \
  bash run_ocaml_bench_gc_sweep.sh

# Frame pointers × flambda (3 invocations):
CONFIG_FILE=src/running/config/experiments/fp_flambda_macrobenchmarks.yml \
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
    ocamlc-self-compile/       # ocamlc on 400k-line generated workload
    liquidsoap-lang/           # liq_bench.ml (parser+typechecker)
    liq-video-frames/          # 1280x720 YUV420 Bigarray frames, refcounted pool (#14533 reproducer)
    merlin/                    # merlin-domains typer (currently disabled)
    js_of_ocaml/               # jsoo on ocamlc.byte → JS
    lavyek/                    # multi-domain Eio + kcas + io_uring KV store

  scripts/
    setup-monorepo.sh          # full setup: pull + patch + build
    vendor-cpdf.sh             # manual vendor for cpdf/camlpdf
    vendor-coq.sh              # manual vendor for rocq + zarith
    vendor-devkit-deps.sh      # manual vendor for libevent/ocurl
    vendor-pplacer.sh          # manual vendor for pplacer+mcl
    vendor-menhir.sh           # manual vendor for menhir
    vendor-alt-ergo.sh         # manual vendor for alt-ergo + deps

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

Each benchmark has `benchmarks/<tool>/<tool>.build.sh`. Build scripts
honor the same env-var contract as [`~/benches/`](https://github.com/ocaml-bench/benches) —
identical names, identical fallbacks, so a script behaves the same way
whether running-ng invokes it or you run it by hand:

| Variable | Meaning | Fallback when unset |
|----------|---------|---------------------|
| `RUNNING_OCAML_BENCH_DIR` | Directory containing this benchmark's sources (`benchmarks/<tool>/`) | The script's own directory (`$(cd "$(dirname "$0")" && pwd)`) |
| `RUNNING_OCAML_OUTPUT` | Path where the built binary must be written | `${BENCH_DIR}/<tool>-${RUNTIME_NAME}` |
| `RUNNING_OCAML_RUNTIME_NAME` | Runtime identifier (e.g. `ocaml-5.4.1`) | `runtime` |
| `RUNNING_OCAML_SWITCH` | Opam switch name (when applicable) | unset |

Because every benchmark lives at `benchmarks/<tool>/` under the monorepo
root, each script derives the monorepo root from `BENCH_DIR` directly
(`$(cd "${BENCH_DIR}/../.." && pwd)`) and invokes `dune build --root <monorepo>`
into a per-runtime `_build-<runtime>/` directory. No macro-specific
env var is needed — the API is the same as `~/benches/`.

All build scripts sanitize the opam environment (`unset OPAM_SWITCH_PREFIX`
etc.) to prevent cross-runtime `.cmi` contamination, and isolate per-runtime
artifacts into `_build-<runtime>/` so concurrent builds for different
runtimes don't clobber each other.

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
- **I/O + multi-domain** — work distributed across N OCaml domains with per-domain syscall traffic (Eio + io_uring); the curve of wall(N) is what's interesting, not any single cell.  
  *Sensitive to:* cross-domain GC marking, major-heap pacer with N writers, `Atomic` contention, `pthread_setaffinity_np` honoring, io_uring stub cost.

---

### Compiler throughput / external work

#### `ocamlc_self_compile` — variant's own ocamlc on a generated workload

**What it does.** Concatenates the 20 classic OCaml-testsuite benchmark files (boyer, nucleic, raytrace, kb, fft, fannkuch_redux, …) from `js_of_ocaml/benchmarks/sources/ml/`, wraps each in a unique module, and replicates the whole set 30× — generating ~400 k lines of real, compiler-stress OCaml code. Then invokes the **variant's own `ocamlc`** (bytecode compiler — *not* `ocamlopt`) on that file. Single observable OCaml process.

**Profile.** wall ≈ 8.6s on `5.4.1/baseline`, gc_overhead 33%, **4384 minor / 16 major collections, 1.0 GB RSS, promoted_pct 12.5%**. Cross-variant spread is small (8.3–10.0s, ~20%) because the workload is uniform.

**OCaml features.**
- **Hashtbl at scale** — `typing/btype.ml:46 module TypeHash = Hashtbl.Make (...)` for type hash-consing, plus environment lookups, scope tables, term-hashing. (We previously claimed this used `Ephemeron`; verified absent — `grep -rn Ephemeron typing/ bytecomp/ driver/ utils/` returns nothing in 5.4.1 *and* in d8bb46c/trunk.)
- **AST allocation** — `Parsetree.structure` blocks per top-level item; lots of small `Location.loc` wrappers.
- **`Format` module** for diagnostic printing (lazily — most warnings don't fire).
- **`Marshal`** — every successful compilation writes a `.cmi` (`file_formats/cmi_format.ml:87` — `Compression.output_value oc (cmi.cmi_name, cmi.cmi_sign)`) and a `.cmo` (`bytecomp/emitcode.ml:33` — `Marshal.to_channel outchan obj`). Bulk Marshal at the end of each compilation.
- **`Bigarray.Array1`** — the bytecode emit buffer is a `(char, int8_unsigned_elt, c_layout) Bigarray.Array1.t` (`bytecomp/emitcode.ml:53`), grown via `Bigarray.Array1.blit`/`sub`. The hot allocation path in bytecode emission goes through Bigarray.
- **Polymorphic `compare` on AST nodes** (used by some passes for canonicalisation).

**Why `ocamlc` (bytecode) and not `ocamlopt` (native).** With `ocamlopt`, flambda variants run *additional* compiler passes (the flambda IR optimisation pipeline) — so cross-variant deltas conflate "runtime perf" with "flambda does extra work". With `ocamlc`, the same pipeline runs everywhere, so cross-variant deltas reflect runtime performance only. (In our 4× 5.4.1 measurement: ocamlc spread is 1.39–1.51s, ≈ 8%; ocamlopt spread is 3.09–6.41s, ≈ 2×.)

**Diagnostic value.** Strongest single signal in the suite for:
- **Marshal** serialisation (`.cmi` + `.cmo` writeout — bulk at end of compilation).
- **Hashtbl** scaling under realistic key/value sizes.
- **Bigarray.Array1** emit-buffer allocation and `blit`/`sub` cost (small, but in the hot bytecode-emission loop).

Pairs with `liq_parse_typecheck` (also AST-shaped). Movement on ocamlc_self_compile but not liq → likely Marshal or `cmi_format`-specific. Movement on both → general AST-allocation path. Movement on `coqc_corelib_stress` *and* `ocamlc_self_compile` → minor-allocator fast path.

#### `jsoo` — js_of_ocaml on the runtime's own `ocamlc.byte`

**What it does.** Runs `js_of_ocaml.exe` on the runtime-under-test's own `ocamlc.byte` (~3.5 MB of bytecode shipped in every OCaml switch), translating it to JavaScript. Exercises jsoo's bytecode parser, SSA / IR pipeline, optimisation passes, and JS code generation. Single observable OCaml process.

**Profile.** wall ≈ 7.2s on `5.4.1/baseline`, gc_overhead 33%, 2260 minor / 28 major collections, ≈ 340 MB RSS. Output is ~2.3 MB of generated JavaScript.

**OCaml features.**
- **Bytecode parsing** — `Parse_bytecode` reads the `.byte` file, decoding instructions, constants, debug info.
- **SSA construction + dataflow analysis** — jsoo's IR is SSA; building it stresses pointer-heavy data structures (CFG, def-use chains).
- **Optimisation passes** — dead code elimination, inlining, escape analysis. Each pass walks the program graph.
- **JS code generation** — string-builder-heavy output writing.
- **Findlib at runtime** — jsoo resolves `+stdlib/` via Findlib to find runtime stubs. Requires `OCAMLPATH` + `OCAMLFIND_CONF` set in the wrapper (see `jsoo.build.sh`).

**Why jsoo's `ocaml-5.6` branch (PR #2227)?** The released js_of_ocaml 6.2.0 has `assert (Ocaml_version.compare current [5; 5] >= 0); failwith "..."` — it hard-rejects OCaml 5.5+. The `ocaml-5.6` branch relaxes the bound to `< 5.7`, covering 5.4.1, 5.5-beta (d8bb46c), and trunk. Vendored via `setup-monorepo.sh`.

**Why Cmdliner 2.1.0?** jsoo's command-line layer uses `Cmdliner.Arg.Completion`, added in Cmdliner 2.0. opam-monorepo's lockfile gives 1.3.0; setup-monorepo.sh swaps in 2.1.0.

**Diagnostic value.** Compiler-throughput benchmark — pairs naturally with `ocamlc_self_compile` (also processes the runtime's own bytecode/AST). Movement on jsoo *and* `ocamlc_self_compile` → suspect minor-allocator fast path (both heavy on small-block allocation). Movement on jsoo alone → suspect Findlib runtime, jsoo's IR construction, or OCaml's compiler-libs (which jsoo uses for bytecode parsing).

Flambda-built jsoo variants should be slower per-invocation than baseline (more passes per file): a compile-time tax distinct from the runtime-perf signal.
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

#### `merlin_bench` — merlin-domains parallel typer

**What it does.** Runs the 7 IDE queries from merlin's own cram bench (`tests/test-dirs/server-tests/bench.t/run.t`) against a 51 319-line synthetic file (mocked Yojson/Jsonrpc/LSP modules), in-process, for N iterations: `construct`, three `complete-prefix` (lines 109 / 51152 / 51319), three `case-analysis` (50796 ×2 + 51318). The two consecutive case-analyses at the same position test the typer cache + partial-typing handoff.

The wrapper exec's a single OCaml binary that does the same `Domain.spawn @@ Mpipeline.domain_typer` dance `ocamlmerlin_server` does in `single` and `server` mode — so we exercise the production code path inside one observable PID. Two domains exactly: main + typer.

**Profile.** Wall ≈ 16s at arg=4, gc_overhead ≈ 24%, RSS ≈ 1 GB. Every iteration triggers cross-domain GC marking as the typer publishes pipeline results back to main — the only suite member that exercises shared-heap synchronization between two real domains.

**OCaml features.**
- **`Domain.spawn` / `Domain.join`** — the typer worker.
- **Effects** for the partial-typing / cancellation control flow (the typer can be aborted mid-run when a new request arrives).
- **`Atomic`** state for the cancellation flag and the shared message channel (`Domain_msg.t`).
- **Cross-domain GC marking** — pipeline results promoted on the typer domain end up reachable from main.
- A real-world OCaml typer workload — covers `Env`, `Typecore`, `Typeclass`, `Marshal` (the typer's caching layer / `persistent_env`). The vendored merlin typer at `duniverse/merlin/src/ocaml/typing/` uses **`Hashtbl.Make`** (not `Ephemeron`) for its type-hash tables, matching upstream OCaml ≥ 5.3. Merlin itself has one `Ephemeron.K1`-backed table (`saved_parts.ml:3`) that stashes parse-tree fragments by gensym'd string — touched at parse time but not in the typer hot path, so this is the *closest thing* to an ephemeron workload in the suite but still cold.

**Diagnostic value.** This is the *only* benchmark that exercises a 2-domain steady-state workload with non-trivial cross-domain communication. What it catches:
- Changes in `Domain.spawn` / `Domain.join` cost (creation/teardown is once per run, but matters at small N).
- Cross-domain GC marking and synchronization (the major-heap pacer's behaviour under 2 producers).
- Atomic / Shared / message-passing primitives under realistic load.
- Effects-handler internals, similar to `eio_fiber_stream` but in a different shape (typer cancellation vs fiber yields).

What it does **not** catch:
- N>2 domain heap contention — only main vs 1 worker. For "many domains marking concurrently", we still need a Sandmark `parallel_binarytrees` import (TODO.md).
- Work-stealing scheduler patterns — merlin uses a single dedicated worker, not a pool.

**Runtime requirement.** Currently disabled. The merlin-domains branch has a non-deterministic race in the typer-domain handoff that fires `Types.rev_log → Invalid -> assert false` at N≥2 iterations of the cram-bench workload. The race fires on **both** 5.4.1 (almost every run) and d8bb46c / 5.5-beta (~50% of N=2 runs in our trials). Initially we suspected an OCaml-version ABI mismatch — the bundled typer is synced from upstream/ocaml_503/ — but the same assertion fires on 5.5-beta, so it's a merlin-domains bug, not a version issue. Source kept; suite entry in `running-ng/.../macrobenchmarks_base.yml` is set to `[]` (empty programs). Full repro + analysis in [`benchmarks/merlin/UPSTREAM_BUG.md`](benchmarks/merlin/UPSTREAM_BUG.md). Re-enable when upstream fixes [#1890](https://github.com/ocaml/merlin/pull/1890).

#### `lavyek_kv_*` — multi-domain Eio + kcas + io_uring key-value store

**What it does.** Lavyek is a from-scratch multicore KV store: Eio for fiber scheduling, kcas for the lock-free in-memory index, io_uring for the WAL writes (per-domain log file). The DaCapo-style driver in [`benchmarks/lavyek/lavyek_bench.ml`](benchmarks/lavyek/lavyek_bench.ml) runs a fixed-work load: WRITE phase puts `nb` = 10 000 000 (key, value) pairs (24-byte key, 100-byte value), then a READ phase verifies all of them. Work is distributed by a shared `Atomic.fetch_and_add` chunk counter (range = 1 op/chunk at max_fibers=100); each domain runs 100 fibers concurrently. Per-domain WAL files live under `benchmarks/lavyek/wal/lavyek_wal_<N>d/` and are removed on clean exit.

Four cells differ only in the domain count: `lavyek_kv_1d` (1 domain), `2d`, `4d`, `8d`. All cells share the same 10 M-op budget, so wall times reflect **parallel scaling** rather than work-budget differences.

**Profile.** Walls on monolith (Ryzen 9 9950X) with re=22, md=8: 1d ≈ 25s, 2d ≈ 14s, 4d ≈ 8s, 8d ≈ 6s. The 4-domain cell is the calibrated target; the 1d cell is the serial baseline for scaling. Notable: I/O matters (per-domain WAL), so on a slow disk the curves flatten; on tmpfs you see ideal scaling out to 4 domains and diminishing returns at 8d (GC pacer + cross-domain kcas contention).

**CPU pinning (deterministic placement across runs).** Each worker domain calls `Processor.Affinity.set_cpus` (from [`ocaml-processor`](https://github.com/haesbaert/ocaml-processor), vendored in `duniverse/processor/`) as the first action inside `fn ()`, locking itself to physical core `id_domain` (the `smt=0` representative — SMT siblings are deliberately not used). Without this, Linux is free to migrate domains around the inherited CPU mask between time slices, which is the dominant source of run-to-run noise on multi-domain Eio workloads. Verified by reading `/proc/<pid>/task/*/status:Cpus_allowed_list`: each domain (and its GC + per-domain io_uring helper threads, which inherit the pthread mask) sits on a single core for the duration of the run. Two early-startup helper threads (the first global `iou-wrk` and the Eio main-setup thread) spawn before `fn ()` runs and so don't get pinned; the `pin_lavyek` modifier (`taskset -c 0-15`) in [`macro_base.yml`](../running-ng/src/running/config/base/ocaml/macro_base.yml) fences them to physical cores too.

**OCaml features.**
- **Multi-domain parallelism** via Eio's `Domain_manager.run` (real OS threads, not just fibers). 1d/2d/4d/8d covers the spectrum: single domain (baseline), low parallelism (2), moderate (4), high (8, > NUMA-node-size on many boxes).
- **Effects** — Eio's `Fiber.fork_promise`, `Fiber.all`, `Fiber.yield`, `Eio.Stream` all go through `Effect.perform` + deep `try_with`. Far more effect traffic than `eio_fiber_stream` (the only other Eio benchmark), spread across multiple domains.
- **Raw `Atomic.*` lock-free structures** — the in-memory index, the compaction queue, and the Bloom filter all use hand-rolled `Atomic.compare_and_set` / `Atomic.fetch_and_add` loops (`duniverse/lavyek/src/memtable.ml`, `chunk_file.ml`, `compact.ml`, `memfilter.ml`). **Note:** lavyek's `dune-project` and `src/dune` list `kcas` + `kcas_data` as dependencies, but `grep -rn 'Kcas\.\|Kcas_data\.\|Loc\.' duniverse/lavyek/src/` returns nothing — the imports are vestigial (see `duniverse/lavyek/REMOVED.md:22`). **No benchmark in the suite actually exercises kcas / lock-free MCAS** — it remains a coverage gap (see below).
- **`Atomic.fetch_and_add`** on a shared counter to dispatch chunks — under heavy contention at 8d, this is itself a measurable cost.
- **io_uring** (via `eio_linux`) for the WAL writes. Each domain creates its own `iou-wrk-*` helper kernel-side thread; per-domain ring size is governed by `OCAMLRUNPARAM` (re=22 → 4 MB ring/domain at md=8).
- **Per-domain `pthread_setaffinity_np`** (via `ocaml-processor`) — the only benchmark in the suite that exercises this; covers a coverage gap that previously made multi-domain timings non-reproducible.

**Diagnostic value.** This is the suite's only **N>2 multi-domain steady-state** workload — it complements `merlin_bench` (when re-enabled), which is exactly 2 domains. What lavyek catches that nothing else does:
- **Cross-domain parallel scaling**. Movement on the 1d→8d *curve shape* (not just absolute walls) → suspect the major-heap pacer, cross-domain marking, or stop-the-world handler cost. Wall on 1d alone (without scaling change) → single-domain Eio scheduler / kcas / io_uring path.
- **`Atomic` contention at high parallelism**. The chunk counter and kcas's internal MCAS both saturate at 8d; movement on 8d alone (1d–4d unchanged) → `Atomic` codegen or memory-barrier insertion regression.
- **io_uring + Eio scheduler**. The only benchmark with real syscall-heavy I/O on the hot path. Pairs with `eio_fiber_stream` only on the Effects axis — lavyek is otherwise a very different shape (I/O-bound, kcas-bound, multi-domain).

Doesn't catch: Domainslib-style work-stealing pools (lavyek uses a manual atomic counter), pure CPU-bound parallel computation (the I/O is always on the path).

**Runtime requirement.** OCaml ≥ 5.2 (Eio 1.x). Requires `md=8` and a smaller per-domain runtime-events ring (`re=22`) — wired via the lavyek-only `re_par` / `md_par` modifiers in [`macro_base.yml`](../running-ng/src/running/config/base/ocaml/macro_base.yml).

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

#### `liq_video_frames_pool` — refcounted-pool video frames (ocaml#14533 reproducer)

**What it does.** Mimics ffmpeg's `AVFrame` lifecycle: each iteration allocates three Bigarrays (Y/U/V planes at 1280×720 YUV420, ~1.32 MiB total) matching `mm/Image.YUV420.create`, fills every pixel (`LIQ_TOUCH=full`), and recycles the buffer via a refcounted pool (`LIQ_POOL=1`). A persistent ~100 MiB OCaml-heap "deadweight" simulates liquidsoap's loaded stdlib + script graph (`LIQ_DW_MB`, default 100). arg=30000 → ~4-20s wall depending on hardware.

**Profile.** Wall and RSS both sensitive to `M` (custom_major_ratio): under M=250 the refcounted-pool path drops CPU significantly with no RSS growth (the shared pool buffer caps committed memory regardless of GC release cadence). At default `(M=44, o=120)` the variant sits near noise-floor vs 5.4.1 — the "free lunch" predicted by #14533 only materialises in the large-M regime.

**OCaml features.**
- **Bigarray** of `Char` — large-allocation custom block path (different code path from `owl_gc`'s small-matrix Bigarrays, which go through minor-heap promotion).
- **Off-heap memory accounting** in the major-heap pacer — `caml_alloc_custom_mem` reports the off-heap size to the GC, which factors it into space_overhead / custom_major_ratio decisions.
- **Refcounted pool semantics** — switching `LIQ_POOL=0→1` isolates the "fresh-malloc per frame" vs "refcounted pool" axis at constant mutator cost (`pool_stubs.c`).
- **Persistent live data** (the deadweight) interacting with the pacer to control major-heap headroom.

**Diagnostic value.** This is the canonical reproduction of toots' [ocaml#14533](https://github.com/ocaml/ocaml/issues/14533) free-lunch shape — the workload Romain Beauxis describes in [the ai-radio blog post](https://www.liquidsoap.info/blog/2024-02-10-video-canvas-and-ai/) ("a short term streaming loop allocating a lot of custom blocks with large external memory"). Headline signals are **`wall_time` and `max_rss_kb`** under an M-sweep. What to look for:
- **Large-M CPU drop with flat RSS** → the predicted #14533 shape; pacer changes have preserved the refcounted-pool fast path.
- **Movement at default `(M=44, o=120)`** → the `caml_alloc_custom_mem` accounting or pacer policy itself changed.

For cross-version regression detection on this workload, sweep `M` and compare wall vs RSS Pareto fronts; a single default-cell read is uninformative.

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
- **`Weak.Make` for term hash-consing** — `alt-ergo/src/lib/util/hconsing.ml:51 module Make (H : HashedType) : S with type elt = H.t = struct let storage = WHT.create initial_size ...` where `WHT = Weak.Make (H_t)`. Every theory term constructor goes through this weak hashset to deduplicate structurally identical subterms. This is the suite's **only** hot-path `Weak`-array workload.
- **`Hashtbl`** at scale for term-hashing (independent of the Weak-hashset above — used in solver state, CDCL clause databases, theory lemma caches).
- **`Sys.set_signal`** — `alt-ergo/src/bin/common/signals_profiling.ml:32-89` installs handlers for `SIGINT` (Ctrl-C), `SIGVTALRM` (`--timelimit` enforcement), `SIGPROF` (profiler). On `alt_ergo_unsat_smt2` the timer is *armed* (`--timelimit 15`) and may fire at the end of a long solve; on `fill`/`yyll` no `--timelimit` is passed so the handlers are registered but inert. **No benchmark stresses high-frequency signal delivery**, but the registration/unregistration path is exercised by all three.

**Diagnostic value.** Three alt-ergo benchmarks (`fill`, `yyll`, `unsat_smt2`) that all move together → suspect alt-ergo's theory backends *or* the `caml_weak_*` runtime (every term construction touches the weak hashset). Movement on only `unsat_smt2` → Dolmen frontend (or signal-handler interaction at timeout). Movement on `fill` and `yyll` but not `unsat_smt2` → native frontend. Movement on all three *but not on any other benchmark* → strongly suspect `Weak.Make` / weak-pointer cleaning.

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
| `liq_video_frames_pool` | 4-20 | low | off-heap (Bigarray, refcounted pool) | custom_major_ratio pacer, refcounted-pool free lunch ([#14533](https://github.com/ocaml/ocaml/issues/14533)) |
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
| `ocamlc_self_compile` | 8.6 | 33 | minor-heavy + Ephemeron | Ephemeron tables, Marshal (.cmi), Hashtbl, AST allocation |
| `jsoo` | 7.2 | 33 | minor + IR construction | jsoo bytecode parser, SSA dataflow, JS codegen |
| `lavyek_kv_1d` | 25 | — | I/O + kcas + Eio | single-domain Eio scheduler, kcas MCAS, io_uring |
| `lavyek_kv_2d` | 14 | — | I/O + multi-domain | 2-domain parallel scaling, cross-domain Atomic contention |
| `lavyek_kv_4d` | 8 | — | I/O + multi-domain | 4-domain parallel scaling (calibrated cell) |
| `lavyek_kv_8d` | 6 | — | I/O + multi-domain | 8-domain scaling, Atomic contention, GC pacer |

### Runtime-feature coverage matrix

Tags are assigned based on **source-grounded** inspection of each
benchmark's hot path: read the driver `.ml` and `grep` the vendored
tool for actual uses of the listed primitive. We do **not** trust
upstream feature lists — only what is reachable from the workload we
run. Notation:

- **●** — used on the workload's hot path.
- **○** — present in the codebase but cold (init only, error path,
  rare event, or a different code path that this workload doesn't
  hit).
- *(empty)* — not used at all.

| Tag | Runtime mechanism | ● hot-path benchmarks | ○ cold benchmarks |
|---|---|---|---|
| **minor-gc** | `caml_alloc_small` fast path, young-ptr bump | coqc_corelib_stress, menhir_*, alt_ergo_*, zarith_pi, sedlex_tokenize, devkit_{network,htmlstream,stre}, cpdf_*, ydump_repeat, liq_parse_typecheck, ocamlc_self_compile, jsoo, ocamlformat_rocq | — |
| **major-promotion** | minor→major copy, slice work | liq_parse_typecheck, ydump_repeat, test_decompress, eio_fiber_stream | most allocation-light benches |
| **custom-block finalisation** | `caml_alloc_custom_mem` + `finalize` cb; `caml_ba_finalize` for Bigarrays | zarith_pi (`Z.t`, `Zarith/caml_z.c:323` via `caml_alloc_custom`), owl_gc (`Bigarray.Array2`, internal `caml_ba_alloc`), liq_video_frames_pool (Y/U/V Bigarrays + `pool_stubs.c` `caml_alloc_custom_mem`), test_decompress (Bigstringaf), devkit_gzip (`z_stream` custom block, `camlzip/zlibstubs.c:61-67`), pplacer (GSL Vector/Matrix, sqlite3 statement handles) | — |
| **explicit `Gc.finalise`** | `caml_final_register` from user OCaml | pplacer (`gsl-ocaml/src/sum.ml:Gc.finalise _free ws`, plus `rng.ml`, `odeiv.ml`, `eigen.ml`, `integration.ml`) | merlin_bench (`mreader_extend.ml:52`, on a process handle — not the merlin_bench query path) |
| **`Bigarray` allocation** | Bigarray `caml_ba_alloc` (custom blocks + off-heap byte data) | owl_gc (100×100 Float64 Array2, hot), liq_video_frames_pool (1280×720 YUV420, hot), test_decompress (Bigstringaf I/O buffers), ocamlc_self_compile (`bytecomp/emitcode.ml:53` — bytecode emit buffer is `(char, int8_unsigned_elt, c_layout) Bigarray.Array1.t`) | — |
| **off-heap accounting / `custom_major_ratio` (M)** | `caml_alloc_custom_mem` mem-tracking → pacer | liq_video_frames_pool (the **only** benchmark whose wall+RSS Pareto front actually moves with M — this is the [#14533](https://github.com/ocaml/ocaml/issues/14533) repro) | owl_gc, zarith_pi, test_decompress all *allocate* custom blocks but at sizes too small to swing pacer policy |
| **`Ephemeron.K1/K2/Kn`** | `caml_ephe_*` | — (**verified gap**) | merlin_bench's `saved_parts.ml:3` (cold; bench disabled), coq's `clib/cEphemeron.ml` (used by VM backend, but `coq_corelib_stress.v` is kernel-only and never touches it) |
| **`Weak.Make` / weak refs** | `caml_weak_*` | alt_ergo_{fill,yyll,unsat_smt2} — `alt-ergo/src/lib/util/hconsing.ml:51 module Make ... WHT.create initial_size` where `WHT = Weak.Make`. Every theory-term constructor goes through this weak hashset. **Suite's only hot-path Weak workload.** | — |
| **`Marshal.{to,from}_*`** | `caml_output_value*` / `caml_input_value*` | ocamlc_self_compile (`.cmi` via `file_formats/cmi_format.ml:87`; `.cmo` via `bytecomp/emitcode.ml:33`) | liquidsoap-lang (`cache.ml:75` — disabled at default), jsoo (`compiler/lib/parse_bytecode.ml:462` — one-shot custom-block introspection), coq (`nativevalues.ml` — native backend not exercised by `coq_corelib_stress.v`), merlin's `persistent_env` (cold), alt-ergo (`satml.ml:2206` — commented out) |
| **`Effect.perform` (OCaml 5)** | `caml_perform_*`, deep `try_with` | eio_fiber_stream (every `Eio.Stream.add/take` and `Fiber.both/all` performs effects — `lib_eio/core/suspend.ml:6`, `fiber.ml:11`, `cancel.ml`), lavyek_kv_*d (every fiber spawn/yield/await — far higher rate than eio_fiber_stream because of many fibers × N domains) | merlin_bench's cancellation control flow (disabled) |
| **`Domain.spawn` / `Domain.join`** | `caml_domain_*` | lavyek_kv_{2,4,8}d (via `Eio.Domain_manager.run` — real OS threads, one per domain), merlin_bench (one typer worker — disabled) | lavyek_kv_1d (allocates a domain manager but never spawns a child domain) |
| **`Atomic.*` (hot)** | `caml_atomic_*` | lavyek_kv_*d (`chunk_file.ml`, `memtable.ml:25-67`, `memfilter.ml`, `compact.ml` — CAS loops on bucket arrays, Bloom-filter bits, compaction queues; also `lavyek_bench.ml`'s `Atomic.fetch_and_add` chunk dispatcher), eio_fiber_stream (`lib_eio/sem_state.ml`, `lazy.ml` — Atomic exchange / CAS on every Stream op), merlin_bench (`Domain_msg.t` cancellation flag — disabled) | ocaml-re internals do Atomic at *regex compile time*, so devkit_{stre,htmlstream,network,gzip} see Atomic only in compile-once init |
| **kcas / lock-free MCAS** | n/a (library-level) | — (**verified gap**: lavyek's `dune-project` imports `kcas` + `kcas_data` but `grep -rn 'Kcas\.\|Kcas_data\.\|Loc\.' duniverse/lavyek/src/` returns nothing; see `duniverse/lavyek/REMOVED.md:22`) | — |
| **`Sys.set_signal`** | `caml_install_signal_handler` | alt_ergo_unsat_smt2 (`--timelimit 15` *arms* `SIGVTALRM` via `alt-ergo/src/bin/common/signals_profiling.ml:32`; fires if solving runs over) | alt_ergo_{fill,yyll} (`SIGINT`+`SIGPROF` handlers installed but never fire); coq has its own SIGINT for Ctrl-C but the kernel-only workload doesn't trigger it. **No benchmark exercises high-frequency signal delivery.** |
| **`Lazy.force` (hot)** | `caml_call_lazy` | liq_parse_typecheck (`typechecking.ml:386`), jsoo (`inline.ml:195,429,714` — `in_loop` and `has_closures` forced per inline decision), menhir_* (`invariant.ml` — invariants forced during conflict resolution) | many cold init lazies (alt-ergo profiling stats, decompress error formatting, ocaml-re regex compile) |
| **`Format` (hot)** | `Format.{fprintf,pp_*}` | menhir_* (codegen + table dumps), ocamlformat_rocq (the entire workload), liq_parse_typecheck (type printing), alt_ergo_* (debug + diagnostic output even when not enabled), zarith_pi (`Z.output` via Printf/Format) | most other benches use Format only on error paths that don't fire |
| **`Hashtbl` at scale** | `caml_hash` | menhir_* (LR state tables — `LRijkstraClassic.ml:849` hash-cons of states; conflict tables), ocamlc_self_compile (`typing/btype.ml:46 module TypeHash`), alt_ergo_* (solver state, CDCL clause db), cpdf_* (`camlpdf/pdf.ml:118` — object map of `(int, objectdata ref * int) Hashtbl.t`), irmin_mem_rw (`irmin_mem.ml:44`), liq_parse_typecheck (`repr.ml:97,100,104,136,155,158` — `evars` tables), pplacer (`vendor/pplacer/pdprune_src/ptree.ml:4` — phylo tree `(int, edge) Hashtbl.t`), devkit_* (NAT tables, transformation caches) | most others touch Hashtbl only at trivial scale |
| **Lwt promises** | `Lwt.bind` continuations | irmin_mem_rw (every store op — write 3 000, read 3 000, then 20 000 mixed) | — |
| **Eio fibers (effects layer)** | `Eio.Fiber.*`, `Eio.Stream`, `Eio.Switch` | eio_fiber_stream, lavyek_kv_*d | — |
| **io_uring (real syscalls)** | `Uring.t` via `eio_linux` stubs | lavyek_kv_*d (per-domain WAL writes — every put goes through the ring) | eio_fiber_stream is pure in-memory Stream; **no io_uring traffic** despite using Eio |
| **CPU pinning** | `pthread_setaffinity_np` via `ocaml-processor` | lavyek_kv_*d (`benchmarks/lavyek/lavyek_bench.ml:59` — `Processor.Affinity.set_cpus`) | — |
| **OpenBLAS / GMP / GSL / sqlite3 / zlib C stubs in inner loop** | bulk FFI | owl_gc (OpenBLAS GEMM per `Mat.dot`), zarith_pi (GMP per arithmetic op), pplacer (GSL+sqlite3), devkit_gzip (zlib via `camlzip`) | test_decompress is *pure-OCaml zlib* — explicitly an FFI-free counterpart |
| **`Gc.compact` / `Gc.full_major` forced** | `caml_compact_heap`, `caml_finish_major_cycle` | — (**verified gap**) | eio's `bench/` utilities call `Gc.full_major` but only outside the benchmark hot path |
| **`Gc.alarm` callbacks** | `caml_final_register_*`-style alarm | — (**verified gap**) | — |

### Per-benchmark tag summary

Reverse index for quick lookup. Hot-path tags only.

| Benchmark | Hot-path tags |
|---|---|
| `coqc_corelib_stress` | minor-gc, constructor-alloc |
| `eio_fiber_stream` | effects, atomics, eio-fibers, major-promotion |
| `merlin_bench` *(disabled)* | domains, effects, atomics, hashtbl, format; cold: ephemerons, Gc.finalise |
| `lavyek_kv_1d` | atomics, effects, eio-fibers, io-uring, pthread-affinity, hashtbl |
| `lavyek_kv_{2,4,8}d` | **domains**, atomics, effects, eio-fibers, io-uring, pthread-affinity, hashtbl |
| `liq_parse_typecheck` | hashtbl, lazy, format, major-promotion, minor-gc |
| `ydump_repeat` | minor-gc, major-promotion, recursive-variants |
| `test_decompress` | bigarray, custom-block-finalisation (Bigstringaf), major-promotion (pure-OCaml zlib) |
| `pplacer_testsuite` | **Gc.finalise**, custom-block-finalisation (GSL+sqlite3), ffi-stubs, hashtbl, minor-gc |
| `owl_gc` | bigarray, custom-block-finalisation (Bigarray Array2), ffi-stubs (OpenBLAS), minor-gc |
| `liq_video_frames_pool` | bigarray, custom-block-finalisation, **off-heap accounting (M-sweep)** |
| `zarith_pi` | custom-block-finalisation (`Z.t`), ffi-stubs (GMP), minor-gc, format(cold) |
| `devkit_gzip` | custom-block-finalisation (z_stream), ffi-stubs (zlib), hashtbl, buffer |
| `devkit_stre` | hashtbl, minor-gc, buffer, string-allocator |
| `devkit_network` | hashtbl, int32-boxing, minor-gc |
| `devkit_htmlstream` | hashtbl, buffer, minor-gc |
| `sedlex_tokenize` | bytes, ppx-match, string-allocator, minor-gc |
| `ocamlformat_rocq` | **format**, buffer, minor-gc |
| `cpdf_{merge,blacktext,scale,squeeze}` | hashtbl (object map), bytes mutation, minor-gc; no FFI |
| `alt_ergo_fill, alt_ergo_yyll` | **weak-refs (Weak.Make hash-consing)**, hashtbl, format |
| `alt_ergo_unsat_smt2` | **weak-refs**, hashtbl, format, **signals (SIGVTALRM armed by `--timelimit 15`)** |
| `menhir_{ocamly,sql_parser,sysver}` | hashtbl, format, lazy, minor-gc |
| `ocamlc_self_compile` | hashtbl, **marshal (`.cmi`+`.cmo` writeout)**, bigarray (emit buffer), minor-gc |
| `jsoo` | hashtbl, lazy, marshal(cold) |

### Coverage gaps — verified

A regression in any of these areas would **not** be caught by the
current suite. Each entry was checked by `grep -rn` against the actual
vendored source.

- **`Ephemeron.K1 / K2 / Kn`** — verified **gap**. The OCaml compiler-libs at 5.4.1 and trunk use `Hashtbl.Make` (not `Ephemeron`) for type hash-consing in `typing/btype.ml` and `typing/types.ml`. Merlin has one cold use in `saved_parts.ml` (and merlin_bench is disabled anyway). Coq's `clib/cEphemeron.ml` is only reached by the VM backend, which `coq_corelib_stress.v` (kernel reduction only) does not exercise. **No benchmark exercises ephemerons on a hot path.** This is the cleanest gap in the suite.
- **kcas / lock-free MCAS** — verified **gap**. Lavyek imports `kcas`/`kcas_data` in `dune-project` but `grep -rn 'Kcas\.\|Kcas_data\.\|Loc\.' duniverse/lavyek/src/` returns nothing — the imports are vestigial (`duniverse/lavyek/REMOVED.md:22` documents the removal of `Kcas_data.Queue`). A small standalone benchmark wrapping `kcas` directly would close this.
- **Domainslib work-stealing pools** — still uncovered (lavyek dispatches via a manual `Atomic.fetch_and_add` counter; eio uses fibers, not work-stealing).
- **`Gc.compact` / `Gc.full_major` in a hot loop** — no benchmark forces a full GC. Compaction interaction with finalisers is therefore untested by user-forced path; the runtime is free to compact on its own schedule but a forced-compact benchmark would catch interaction bugs.
- **`Gc.alarm` / `Gc.create_alarm`** — no benchmark registers one. If alarm machinery changed, the suite would silently miss it.
- **High-frequency signal delivery in tight loops** — alt-ergo *registers* signal handlers (SIGVTALRM/SIGINT/SIGPROF) but they fire at most once per run. No benchmark exercises rapid user-signal delivery.
- **Pure-OCaml hot inner-loop float computation** isolating flambda — owl_gc defers to OpenBLAS, so flambda has nothing to optimise in the inner loop. A pure-OCaml numerical kernel (`Array.iter`, no allocation in the inner loop) would catch flambda regressions cleanly. Phase 2 candidate (raytracer / nbody from Sandmark).
- **`Bigarray` slicing and reshape patterns** — owl_gc creates and uses Array2 but doesn't exercise slicing-heavy patterns; liq_video_frames_pool fills planes without slicing.
- **Polling-points / safe-point density** — no benchmark stresses the cooperative-cancellation path that depends on poll-insertion frequency.
- **Direct user `Effect` handlers** (outside Eio) — every effect-perform in the suite goes through Eio's handlers. A bug specific to a user-defined `Effect.Deep.try_with` outside Eio would slip through.

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
| `liq_video_frames_pool` | `Sys.argv.(1)` | Number of frames to allocate (default 30000). RSS + wall under M-sweep |

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
4. Update `running-ng/src/running/config/base/ocaml/macro_base.yml`'s
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
| 8 | `duniverse/js_of_ocaml/.../dune` | Remove public_name | Vendored executable |
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

- **OxCaml**: Only menhir, test_decompress, and zarith_pi work.  Other
  tools fail due to locality type annotation errors in vendored
  ecosystem packages.

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
5. Add to `running-ng/src/running/config/experiments/macrobenchmarks_monorepo.yml`
6. Add to the test build list in `scripts/setup-monorepo.sh`
7. Test: `make clean-all && make setup`
