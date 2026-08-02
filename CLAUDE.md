# CLAUDE.md — working notes for agents & contributors on `macro-benches`

Auto-loaded context for Claude Code (and a reference for contributors). The
human-facing docs are `README.md` and the per-benchmark pages under
`docs/benchmarks/<name>.md`. This file holds the operational and machine-facing
detail that doesn't belong in either: the build-script contract, the in-process
iteration and ring-size mechanics, the vendored-source patch table, the
runtime-feature coverage matrix and gaps, the gotchas, and the backlog.

## What this is

- A **dune monorepo** of real-world OCaml programs used as macro-benchmarks (coq,
  frama-c, goblint, alt-ergo, menhir, cpdf, owl, jsoo, irmin, liquidsoap,
  ocamlformat, decompress, eio, sedlex, yojson, zarith, pplacer, devkit, …). All
  third-party deps are **vendored** under `duniverse/` (opam-monorepo), so every
  runtime compiles byte-identical source. 20 active tools, 31 programs; `merlin`
  and `lavyek` ship in the tree but are disabled (see their doc pages).
- Driven by `~/running-ng` (suite type `OCamlBenchmarkSuite`, **not** the
  satellite-switch path): each benchmark has `benchmarks/<tool>/<tool>.build.sh` that
  runs `dune build` with the runtime compiler on PATH, into a **per-runtime build dir**
  `_build-<runtime>`, then copies/links out the binary `benchmarks/<tool>/<prog>-<runtime>`.

## Hard rules (do not violate)

- **Do not comment on PRs, or add to PRs, unless explicitly asked to.**
- No "Claude"/Anthropic/Co-Authored-By: Claude in further commit messages.
- **Remote is `origin = github.com/ocaml-bench/macro-benches`** — a *shared org*
  repo, not a personal fork. Be careful pushing; commit/push only when asked.
- **Never delete an individual file inside a `_build-<runtime>/` tree** to "force a
  rebuild" — it corrupts dune's incremental state (you'll get `*.impl.d: No such file`
  / missing `.sexp`). To force a re-probe/rebuild, remove the **whole**
  `_build-<runtime>` dir (or `dune clean`), and delete the benchmark's **output**
  binary so running-ng rebuilds it.
- **Don't commit `_build-*/`, `_rocq_prefix/`, big inputs, or vendored-source churn**
  casually. `duniverse/` is generated (opam-monorepo); regenerate via `scripts/`.
- Keep documentation consistent with every commit: `README.md`, the relevant
  `docs/benchmarks/<name>.md`, and this file.

## Where things live (read first)

- `benchmarks/<tool>/` — `<tool>.build.sh` (called by running-ng) + input data.
- `benchmarks/manifest.yml` — **the program list**: name → tool, build script, args.
  Needed because several build scripts derive their dune target from the *output
  filename*, so the scripts alone don't say what programs exist. CI reads this.
- `docs/benchmarks/<name>.md` — human-facing page per benchmark.
- `duniverse/` — vendored dependency sources (the actual compiled code).
- `vendor/` — manually vendored bits (camlpdf, cpdf-source, zarith, pplacer, frama-c, apron, …).
- `scripts/` — `setup-monorepo.sh`, `vendor-*.sh` (coq, apron, frama-c, cpdf, …),
  `ci-build-all.sh` / `ci-run-all.sh` / `ci-manifest.py` (the CI phases).
- `.github/workflows/ci.yml` — master-only build + run-once gate (see §CI).
- `sources.yml`, `macro-bench-*.opam(.template)`, `dune-workspace`, `dune-overlays`.
- `_build-<runtime>/` — per-runtime dune build output (gitignored).

## Build / run

running-ng calls `<tool>.build.sh` with the runtime compiler on PATH and the env
vars below. Scripts `unset` opam/OCAML env vars to avoid cross-runtime `.cmi`
contamination, then `dune build --root <monorepo> --build-dir _build-<runtime>
--profile release <target>` and copy the result out. Because every benchmark
lives at `benchmarks/<tool>/`, each script derives the monorepo root from
`BENCH_DIR` (`$(cd "${BENCH_DIR}/../.." && pwd)`); no macro-specific env var is
needed, and the contract matches `~/benches/` name-for-name.

| Variable | Meaning | Fallback when unset |
|----------|---------|---------------------|
| `RUNNING_OCAML_BENCH_DIR` | Directory with this benchmark's sources (`benchmarks/<tool>/`) | the script's own directory |
| `RUNNING_OCAML_OUTPUT` | Path where the built binary must be written | `${BENCH_DIR}/<tool>-${RUNTIME_NAME}` |
| `RUNNING_OCAML_RUNTIME_NAME` | Runtime identifier (e.g. `ocaml-5.4.1`) | `runtime` |
| `RUNNING_OCAML_SWITCH` | Opam switch name (when applicable) | unset |
| `RUNNING_OCAML_SWITCH_PREFIX` | Prefix of the runtime's switch. Only `ocamlc-self-compile` and `jsoo` need it — they run the runtime's *own* `ocamlc` / `ocamlc.byte` as the workload, so they need the switch, not just a compiler on PATH | `~/.opam/running-ng-<RUNTIME_TAG>` if it exists, else the prefix of the `ocamlc` on PATH |

Standalone usage (no running-ng): set `RUNNING_MACRO_BENCH_DIR=~/macro-benches` and
drive `~/running-ng`'s `build_ocaml_binaries_gc_sweep.sh` / `run_ocaml_bench_gc_sweep.sh`.
Or drive the build straight from the manifest: `bash scripts/ci-build-all.sh`.

## CI

`.github/workflows/ci.yml` runs on **pull requests into `master`** and on **pushes
to `master`** (plus a weekly cron and `workflow_dispatch`); nothing runs on other
branch pushes. The PR run is the gate; the post-merge run exists because the
required check is not `strict`, so two PRs can each be green against an older
`master` and still break it together — without a push run, nothing would notice
until the next PR or the Monday cron. It is cheap (same cache key as the PR run
that just passed) and it refreshes the cache in `master`'s scope, which is the only
scope every PR can restore from. Note `cancel-in-progress` is deliberately limited
to PR runs: superseding a PR run is right, but cancelling a `master` run would
leave the merge that triggered it unverified.

Two matrix legs: the
**latest stable release**, which gates, and the **`ocaml/ocaml` trunk tip**, which
is `continue-on-error` because it tracks a moving compiler and needs ppxlib/lwt
git `main` (patches 4+5 below). The trunk leg resolves the tip commit *before*
creating the switch and folds the SHA into every cache key — otherwise a restored
opam-root cache silently tests a stale trunk.

The gate is enforced by branch protection on `master`: the required check is
`build + run once (stable)`. The matrix `label` is deliberately version-free —
GitHub matches required checks **by name**, so putting `5.5.0` in the label would
orphan the requirement the moment the compiler is bumped.

Three phases, all driven off `benchmarks/manifest.yml`:

- `scripts/ci-manifest.py check` — runs first because it costs seconds. It compares
  **sets**, not just counts, in five directions:
  1. every manifest program's tool dir and build script exist;
  2. every `benchmarks/*/*.build.sh` is claimed by a program or listed under
     `disabled:` — this is what catches a whole new benchmark landing with no
     manifest entry;
  3. a build script that dispatches on the program name (`case "${BM_NAME}"`, i.e.
     ahrefs-devkit today) accepts *exactly* the programs the manifest claims for it
     — this is what catches a new program added to an **existing** tool, where the
     build script already exists so (2) stays quiet. Both directions are errors: a
     `case` arm with no manifest entry, and a manifest entry the `case` would reject
     with `Unknown benchmark`;
  4. every in-tree input path in a program's `args` exists, so a program can't be
     added without committing its input. Generated inputs opt out with
     `inputs_generated: true` (only `alt_ergo_fill`, whose `fill_x100.why` is built
     by its build script and gitignored — a fresh checkout does not have it);
  5. one `docs/benchmarks/<tool>.md` per tool, both directions.

  It prints the counts it compared (`22 tools = 20 with programs + 2 disabled`,
  `31 programs`, `22 docs pages`) so the log shows the numbers, then lists every
  problem it found rather than stopping at the first.

- `scripts/ci-build-all.sh` — builds every program into `_build-ci`. Deletes the
  output binary first, so a stale wrapper can't make a build look successful (the
  `exit 127` trap in §Gotchas).
- `scripts/ci-run-all.sh` — runs each program once, with its manifest args, from a
  fresh scratch cwd so relative outputs (menhir's `--base`, goblint's
  `witness.yml`) don't land in the tree.

Neither stops at the first failure: a hermeticity break usually takes several
benchmarks with it, and one run should show all of them. Both write a table to
`$GITHUB_STEP_SUMMARY` and leave per-program logs in `ci-logs/`.

Notes for whoever touches this next:

- **`args` in the manifest are copied verbatim from running-ng's `macro_base.yml`**
  so the two lists can be diffed mechanically. Keep it that way.
- **`expected_exit`** declares a by-design non-zero exit. Only `alt_ergo_unsat_smt2`
  needs it today: `--timelimit 15` means the workload *is* "solve for 15 s", the goal
  never closes, and alt-ergo dies of its own SIGVTALRM (128+14 = **142**) on every
  run. Don't "fix" that by dropping the flag — the time limit is the workload.
- **In the manifest rows, `args` is the last column on purpose.** Bash treats TAB as
  whitespace-IFS, so an empty field mid-row collapses and shifts every later column;
  the programs with no args would silently take the next field as their argv.
- **Ladder rungs are deliberately absent.** The base rung is the signal CI needs,
  and the big rungs don't fit a hosted runner (sedlex's large rung peaks near
  27 GB RSS). When rungs land on master, list only the `_small` one.
- **`SKIP_TEST_BUILD=1`** makes `setup-monorepo.sh` skip its `[9/9]` test build.
  CI sets it because that step targets the default `_build/` while the build
  scripts target `_build-<tag>/` — running both compiles the duniverse twice.
- **Dune is pinned per leg**: `3.22.1` on stable, git `main` on trunk (released
  dune can't bootstrap against 5.6). Patch 19 is what lets the trunk leg work at
  all — its dune is ≥ 3.24, which deleted the `coq` extension vendored rocq
  declared. The stable pin is for determinism, not necessity: the workspace parses
  under both 3.22.1 and 3.24 now, and pinning keeps the build environment fixed
  the same way every source is pinned.
- The **weekly cron run skips the cache** on purpose. Everything is pinned now
  (see §Vendored source pins), so this is not a drift detector — it is a check
  that a *cold* setup still works: that every pinned commit and tarball is still
  fetchable, that the rocq bootstrap works from nothing, and that the cache we
  rely on the rest of the week isn't hiding a broken setup path.

## Vendored source pins

`sources.yml` is the single source of truth for every third-party version this
repo vendors, and `scripts/lib-sources.sh` is how the scripts read it:

- `src_field <key> <field>` — one field out of `sources.yml`. Deliberately awk, not
  PyYAML, so setup still works on a machine with only bash, git, curl and a
  compiler.
- `clone_pinned <key> <dir>` — clone a git source at its pinned commit. Idempotent
  (no-op when the checkout is already at the pin), and it *re-clones when the pin
  moves*, which the old "does the directory exist?" checks could not detect. It
  keeps `.git`, so `git -C <dir> rev-parse HEAD` tells you what you have.

Nothing tracks a branch HEAD any more. Six sources used to — ppxlib, lwt, merlin,
js_of_ocaml, pplacer, mcl — which meant a cold `make setup` vendored whatever
upstream had that morning, silently changing the benchmark binaries and therefore
the measurements. When they were pinned, ppxlib had already drifted 7 weeks past
the validated tree and lwt 3 months; the js_of_ocaml branch had been squashed and
deleted upstream, so a cold clone failed outright.

Consequences worth knowing:

- **js_of_ocaml is pinned to a `master` commit**, not the old `ocaml-5.6` PR
  branch: the 5.6 support landed on master (the `[ 5; 7 ]` bound in
  `compiler/lib/magic_number.ml`) and the branch is gone. Bumping this pin changes
  *two* benchmarks — `ocamlc_self_compile` takes its workload from
  `duniverse/js_of_ocaml/benchmarks/sources/ml`.
- **Pins are commits, never tags.** A tag can be re-pointed upstream. Watch for
  annotated tags when resolving one: `git ls-remote <url> 'refs/tags/<t>^{}'`
  gives the commit, while plain `refs/tags/<t>` gives the tag object.
- **`clone_pinned` tries three fetches**: the commit directly (GitHub allows it);
  else the recorded branch/tag shallow, then verifies the commit matches (GitLab
  refuses bare commits — this is the frama-c path, and it is still pinned because
  a moved ref fails the verify); else a full clone.
- **`ci-manifest.py check` enforces this**: every `src_field`/`clone_pinned` key
  must exist in `sources.yml` with the fields it asks for, every `commit:` must be
  full 40-hex, and **no script may call `git clone` directly** (only
  `lib-sources.sh`, for the fallback). That last rule is what stops an unpinned
  clone creeping back in.
- Bumping a pin is a one-line edit to `sources.yml` plus `make setup`. It shows up
  in review and CI rebuilds and re-runs everything against it — which is the
  entire point.

## Gotchas (hard-won — don't rediscover)

- **Two kinds of output binary.** Some `<prog>-<runtime>` are **standalone copied
  binaries** (menhir, cpdf, alt-ergo, …); others are **tiny wrapper scripts** that
  `exec` the real `.exe` *inside* `_build-<runtime>/…` (coqc, owl, devkit, jsoo,
  goblint, frama-c, pplacer, liq_video_frames, …). Deleting `_build-<runtime>` leaves
  the wrappers in place, so running-ng thinks they're built, **skips rebuild, and the
  wrapper fails at run with `exit 127, .exe: No such file`** — *not* an MMTk/runtime
  bug. Re-`buildbms` after deleting the wrapper output to regenerate the `.exe`.
- **dune caches configurator probes in `_build`** (e.g. `lwt_features.h`, `*.sexp`).
  An env-var change (e.g. `LIBRARY_PATH`) alone won't re-probe — needs a clean build dir.
- **The duniverse builds across multiple compilers** (5.4.1, `d8bb46c`, trunk,
  5.5.0-rc1, ocaml-mmtk). All programs build on stock 5.5.0-rc1.
- **External C deps:** apron (goblint) needs camlidl + gmp/mpfr; owl needs
  openblas/cblas; cpdf needs camlpdf; these come via `vendor/` + `scripts/vendor-*.sh`.
- **Under ocaml-mmtk** (built via running-ng's `OCamlMMTk`): all 31 *build* (the
  runtime supplies `LIBRARY_PATH`+heap), but a few **crash at run** — see MMTk notes.

## Per-session workflow

1. Identify which benchmark/tool you're touching; its build glue is
   `benchmarks/<tool>/<tool>.build.sh`; its source is under `duniverse/` or `vendor/`;
   its human doc is `docs/benchmarks/<tool>.md`.
2. Build via running-ng with `RUNNING_MACRO_BENCH_DIR` set; don't hand-delete `_build`
   internals.
3. Commit only when asked; don't commit build output.

---

## Iteration counts (in-process loops)

A few benchmarks have per-invocation work that's too short to measure reliably —
startup overhead dominates and observability tools (olly, perf) lose precision.
Two patterns are in use.

**Shell-loop wrapper** (legacy, *broken for olly*). Some build scripts generate a
wrapper that runs the binary `N` times in a shell loop (`for _ in $(seq 1 N); do
"$REAL_EXE"; done`). This works for wall-time aggregation but breaks olly's
runtime_events attach model: olly sees one OCaml process at a time. With short
per-child work the events files stack in `/tmp` and olly aggregates them; with
longer per-child work (e.g. `pplacer_testsuite` at ~3.5 s/child) olly attaches to
the first child only and silently misses the other N−1.

**Env-var / argv in-process loop** (recommended). The OCaml entry point reads a
count and runs the work N times inside the same process; the wrapper just sets the
count and `exec`s the binary. The orchestrator's positional arg becomes the loop
count, one process does N iterations, olly observes the whole thing.

In use by:

| Benchmark | Count via | Notes |
|---|---|---|
| `pplacer_testsuite` | `PPLACER_TEST_LOOP` env var | OUnit runner; env var avoids clashing with OUnit's argv parsing |
| `owl_gc` | `Sys.argv.(1)` | plain main; argv otherwise unused (default 1) |
| `devkit_stre` | `Sys.argv.(1)` | loops the 8 sub-benches (default 1) |
| `devkit_gzip` | `Sys.argv.(1)` | same shape as stre |
| `devkit_network` | `Sys.argv.(1)` | same shape as stre |
| `liq_video_frames_pool` | `Sys.argv.(1)` | number of frames (Knob B); `argv.2`/`argv.3` = frame width/height (Knob A = resolution) |

Note: `devkit_htmlstream` is **not** in this list — it runs fixed internal
`for _ = 1 to 10` loops and is copied out as a standalone binary, so it ignores
`Sys.argv`. (The top summary table in older READMEs over-generalised this.)

**Ring-size interaction.** One process accumulating events across N iterations
needs a bigger `runtime_events` ring than N separate processes. For
allocation-heavy benches (owl_gc especially) large counts overflow the ring and
olly reports lost events plus a corrupted `wall_time`. Convention: `re-25` (32 MB)
for the in-process-loop benches; bump to `re-26` (64 MB) if a new one hits the
limit. Empirical owl_gc sizing: `re-23` (8 MB) starts corrupting `wall_time` at
arg 5; `re-25` is clean through arg 6 (~16s), the current setting.

When porting a benchmark to this pattern: wrap the entry point with a count
(default 1; env var if it already parses argv, else `Sys.argv.(1)`), drop the
shell `for` loop in the build script, set the orchestrator `args:` to the count,
and if the entry point is upstream code record the patch in `setup-monorepo.sh` so
it survives a re-vendor.

## MMTk (`ocaml-mmtk`) notes

Built via running-ng's `OCamlMMTk` runtime type (OCaml 5.5 + the MMTk collector).
All 31 programs build; 27 run cleanly under both native plans (Immix,
StickyImmix). Known MMTk-only issues:

- **Crashes (4 programs).** `alt_ergo_{fill,yyll,unsat_smt2}` SIGSEGV (the moving
  collector relocates a value a C stub holds a raw pointer to, via zarith→GMP; runs
  fine under a non-moving MMTk build, so it's a moving-GC / object-pinning gap) and
  `pplacer_testsuite` SIGABRT (a channel finaliser locks an already-closed channel
  mutex during GC). Both are excluded from the running-ng MMTk configs.
- **Off-heap is not GC-paced.** `MMTK_HEAP_SIZE_MB` bounds only on-heap memory.
  Custom-block off-heap data (Bigarray bulk data in `owl_gc`, GMP limbs in
  `zarith_pi`) is freed by the block's finaliser only when the proxy is collected,
  but MMTk paces on on-heap occupancy, so off-heap bytes accumulate with the heap
  budget: `owl_gc` RSS goes from ~130 MB at a 3 MB heap to ~12 GB at a 16 GB heap
  with the same live set. Stock OCaml paces the major GC on off-heap memory via
  `caml_alloc_custom_mem`; under MMTk that path is currently inert. These benches
  are poor footprint signals under MMTk.

## Benchmark quick-reference cross-table

| Benchmark | wall (s) | gc% | Allocation profile | Strongest signal for |
|---|---|---|---|---|
| `coqc_corelib_stress` | 17 | 94 | minor-saturation | minor-GC fast path (mixed fib/ack/tree; old 52s stale) |
| `coqc_tree_small` | 5.3 | 90 | minor-saturation (D=17, 0.57GB) | minor-GC fast path (Knob A = make_tree depth) |
| `coqc_tree_default` | 19 | 94 | minor-saturation (D=18, 0.98GB) | as small, deeper reduction |
| `coqc_tree_large` | 69 | 97 | minor-saturation (D=19, 1.89GB, 64ms max pause) | minor-GC saturation at scale (highest gc% in suite) |
| `eio_fiber_stream` | 6 | 10 | promotion-heavy | OCaml 5 effects, fiber scheduler |
| `irmin_mem_rw` | 12 | 11 | medium | Lwt, persistent hash-tree (Knob-B, 3000 keys + 20000 ops) |
| `irmin_mem_rw_small` | 5 | 20 | churn (6000-key store, 31MB) | Lwt + persistent-hash-tree churn (Knob A = store size; O(n_keys²) write) |
| `irmin_mem_rw_default` | 16 | 25 | churn (10000-key store, 44MB) | as small, more churn |
| `irmin_mem_rw_large` | 52 | 29 | churn (18000-key store, 74MB) | hash-tree/Hashtbl churn at scale (RSS small; churn ladder, gc% rises) |
| `liq_parse_typecheck` | 26 | 22 | promotion-heavy (48%) | AST + minor-to-major copy (Knob-B, 50000× fixed script) |
| `liq_parse_typecheck_small` | 5 | 59 | promotion-heavy (0.22, 0.26GB) | parse+typecheck AST/type-env at scale (Knob A = script size, generated units) |
| `liq_parse_typecheck_default` | 14 | 60 | promotion-heavy (0.44GB) | as small, bigger AST + type env |
| `liq_parse_typecheck_large` | 64 | 59 | promotion-heavy (12k units, 0.72GB) | promotion + type-inference throughput at scale (~60% gc%, super-quadratic wall) |
| `ydump_repeat` | 5.5 | 4.5 | promotion-heavy (65%) | recursive variants, JSON tree |
| `ydump_repeat_small` | 5.5 | 29 | promotion-heavy (28%, 3.25GB) | promotion + major-GC pauses on a boxed JSON tree (Knob A = doc size) |
| `ydump_repeat_default` | 16 | 34 | promotion-heavy (10GB) | as small, bigger tree |
| `ydump_repeat_large` | 33 | 40 | promotion-heavy (1.5GB doc, 20GB, 424ms max pause) | promotion throughput + largest major-GC pauses in suite (pointer-dense tree) |
| `test_decompress` | 5 | 2.4 | promotion-heavy + Bigstring | Bigstring header allocation |
| `test_decompress_small` | 5 | 0.8 | compute + Bigstring (80MB payload, 0.5GB) | DEFLATE codegen/compute (least GC-bound bench; Knob A = payload size) |
| `test_decompress_default` | 16 | 0.8 | compute + Bigstring (256MB, 1.4GB) | as small, bigger payload |
| `test_decompress_large` | 63 | 0.9 | compute + Bigstring (1GB, 5.7GB) | pure DEFLATE compute/codegen at scale (compute-bound control) |
| `pplacer_testsuite` | 13 | 70 | major-heavy (FFI) | gsl/sqlite3, tree allocation |
| `pplacer_like_small` | 4.7 | 0.6 | off-heap GSL Glv (0.22GB, 17.6k sites) | Knob A = likelihood n_sites (Felsenstein + ML pendant scan) |
| `pplacer_like_default` | 15 | 0.6 | off-heap GSL Glv (0.65GB, 55k sites) | as small, bigger alignment |
| `pplacer_like_large` | 51 | 0.6 | off-heap GSL Glv (2.18GB, 187k sites) | compute-bound; gc%~0, read by RSS/alloc_words |
| `owl_gc` | 16 | 50 | off-heap (Bigarray, small) | Bigarray finalisation, OpenBLAS stubs |
| `owl_gc_small` | 4 | 24 | off-heap (dim 300, 95MB) | Bigarray finalisation, off-heap footprint (Knob A = dim) |
| `owl_gc_default` | 14 | 11 | off-heap (dim 500, 230MB) | as small, bigger live set |
| `owl_gc_large` | 124 | 8 | off-heap (dim 1500, 1.9GB, 27ms max pause) | off-heap footprint + GC latency + custom-block pacer (M) |
| `owl_gc_huge` | 453 | 8 | off-heap (dim 2400, 4.77GB, 53ms max pause / 25ms p99.9) | off-heap footprint at scale + GC latency + pacer (M) |
| `zarith_pi` | 8 | 27 | off-heap (GMP custom blocks) | custom-block path, GMP stubs |
| `liq_video_frames_pool` | 4-20 | low | off-heap (Bigarray, refcounted pool) | custom_major_ratio pacer, refcounted-pool free lunch (#14533); frozen repro (720p×30000) |
| `liq_video_frames_pool_small` | 5.6 | 95 | off-heap pacer (1080p, 1104 majorGC) | custom_major_ratio pacing (Knob A = frame resolution) |
| `liq_video_frames_pool_default` | 22 | 94 | off-heap pacer (4K, 4413 majorGC) | as small, bigger per-frame off-heap |
| `liq_video_frames_pool_large` | 101 | 79 | off-heap pacer (8K, 16837 majorGC, ~5ms pauses) | major-GC pacing at scale (majorGC ∝ pixels²; RSS flat, read by collection counts) |
| `devkit_gzip` | 10 | 1 | compute-bound | codegen, zlib stubs |
| `devkit_stre` | 14 | 5.5 | minor + retention | string allocator, generational copy |
| `devkit_network` | 17 | 4.5 | minor (Int32) | int32 boxing, Hashtbl |
| `devkit_htmlstream` | 25 | 3.3 | minor + retention | Buffer allocator |
| `sedlex_tokenize` | 5 | 40 | minor-saturation | string allocation, PPX DFA |
| `sedlex_tokenize_small` | 5 | 43 | minor + retained token list (2M lines, 2.7GB) | minor-GC + promotion under a growing live heap (Knob A = # lines) |
| `sedlex_tokenize_default` | 17 | 49 | as small (6M lines, 8GB) | minor-GC/promotion throughput |
| `sedlex_tokenize_large` | 74 | 61 | minor + retained list (20M lines, 27GB, 153ms max pause) | minor-GC/promotion + pause latency under a large mostly-live heap (gc% RISES with size; steepest pauses in suite) |
| `ocamlformat_rocq` | 5 | 30 | minor + AST | Format module, AST allocation |
| `ocamlformat_rocq_small` | 5 | 33 | minor + AST (40k lines, 0.6GB) | Format, AST allocation, minor-GC throughput (Knob A = # lines) |
| `ocamlformat_rocq_default` | 13 | 32 | minor + AST (100k lines, 1.7GB) | as small, bigger live AST |
| `ocamlformat_rocq_large` | 100 | 29 | minor + AST (500k lines, 8.4GB, 90ms max pause) | minor-GC throughput + major-GC scan latency on a multi-GB live AST |
| `cpdf_merge` / `_blacktext` / `_squeeze` | 6-9 | 20-40 | minor + Bytes | Bytes mutation, codegen |
| `cpdf_scale` | 36 | 19 | minor (compute) | codegen of geometry transforms |
| `cpdf_squeeze_small` | 7.4 | 31 | live PDF object map (110M w, merge 8 copies) | Knob A = document working set (merge-N-copies + recompress) |
| `cpdf_squeeze_default` | 18 | 25 | live object map (225M w, 24 copies) | as small, bigger merged doc |
| `cpdf_squeeze_large` | 57 | 16 | live object map (405M w, 64 copies, RSS 3GB) | live-heap-driven; gc% falls as flate C recompress dominates |
| `alt_ergo_fill` | 14 | 40 | promotion-medium | SMT theory backends |
| `alt_ergo_yyll` | 19 | 6 | minor (compute) | native frontend, theory backends |
| `alt_ergo_unsat_smt2` | 15 | 7 | minor (compute) | Dolmen frontend, theory backends |
| `alt_ergo_chain_small` | 4.2 | 14 | live congruence structure (76M w, N=4000) | Knob A = single-solve problem size (chain VC a(i)=a(i-1)+1) |
| `alt_ergo_chain_default` | 14 | 18 | live congruence (244M w, N=7000) | as small, bigger single solve |
| `alt_ergo_chain_large` | 38 | 26 | live congruence (638M w, N=10500, RSS 4.9GB) | heap-scan-bound; gc% RISES, p99.9 pause 22ms |
| `menhir_sysver` | 7.8 | 32 | minor (sysver table, 0.72GB) | Hashtbl growth — Knob-A ladder rung **small** |
| `menhir_ocamly` | 13 | 20 | minor (ocaml canonical LR, 2.76GB) | Hashtbl scale, large arrays — ladder rung **default** |
| `menhir_sysver_canonical` | 34 | 36 | minor (sysver canonical LR, 4.0GB) | canonical state-table explosion — ladder rung **large** |
| `menhir_sql_parser` | 1.2 | 27 | minor (LALR + verbose, 0.31GB) | menhir internals — fast LALR extra, not a ladder rung |
| `ocamlc_self_compile` | 8.6 | 33 | minor-heavy + Marshal | Marshal (`.cmi`/`.cmo`), Hashtbl, Bigarray emit buffer, AST allocation |
| `jsoo` | 7.2 | 33 | minor + IR construction | jsoo bytecode parser, SSA dataflow, JS codegen |
| `jsoo_small` | 5 | 33 | minor + IR (5.6MB bytecode, 0.5GB) | whole-program IR alloc + minor-GC (Knob A = bytecode size) |
| `jsoo_default` | 16 | 31 | minor + IR (14MB, 1.7GB) | as small, bigger IR |
| `jsoo_large` | 50 | 33 | minor + IR (36MB, 7.8GB, 129ms max pause) | IR-alloc throughput + major-GC scan latency on a large SSA graph |
| `goblint` | 0.2-1 | high alloc | high allocation / churn (~1.3GB, 5.6KB input) | allocated_bytes (#13733), hash-consing, apron FFI |
| `frama_c_eva_sqlite_small` | 7 | 13 | weak/ephemeron hash-consing (457MB RSS, promo 0.6%) | ephemeron key-scan (#11733), CIL AST hash-cons, `Weak.Make` at scale |
| `frama_c_eva_sqlite_default` | 16 | 11 | as small, richer domains (641MB RSS, live 77M) | #11733 at higher precision |
| `frama_c_eva_sqlite_large` | 113 | 3 | max ephemeron churn (165k minor GC, 695MB RSS, 3.3s gc_time, 11.5ms tail pause) | #11733 ephemeron-clean throughput + GC latency (widening thrash, precision 3) |

(`merlin_bench` and `lavyek_kv_*` omitted — disabled. frama-c Knob A = `-eva-precision` (2nd
wrapper arg); slevel is inert; no >5min huge rung reachable via EVA knobs — see
`docs/benchmarks/frama-c.md`. gc% FALLS with size (13→11→3%, mutator-bound at large) while
tail pause GROWS (3.1→8.9→11.5ms) — small/default GC-throughput-sensitive, large
GC-latency-sensitive. olly re-25|md-2, 5.5.0, 2026-07-24.)

## Runtime-feature coverage matrix

Tags are assigned from **source-grounded** inspection of each benchmark's hot path
(read the driver `.ml`, `grep` the vendored tool for actual uses). We do not trust
upstream feature lists, only what is reachable from the workload we run. A tag whose
hot-path set is empty is a **coverage gap** (listed below). running-ng exposes these
through a `RUNNING_TAG` selector.

| Tag | Runtime mechanism | hot-path benchmarks | cold |
|---|---|---|---|
| **minor-gc** | `caml_alloc_small` fast path, young-ptr bump | coqc_corelib_stress, menhir_*, alt_ergo_*, zarith_pi, sedlex_tokenize, devkit_{network,htmlstream,stre}, cpdf_*, ydump_repeat, liq_parse_typecheck, ocamlc_self_compile, jsoo, ocamlformat_rocq, goblint | — |
| **major-promotion** | minor→major copy, slice work | liq_parse_typecheck, ydump_repeat, test_decompress, eio_fiber_stream | most allocation-light benches |
| **custom-block finalisation** | `caml_alloc_custom_mem` + `finalize` cb; `caml_ba_finalize` | zarith_pi (`Z.t`, `caml_z.c:323`), owl_gc (`Bigarray.Array2`), liq_video_frames_pool (Y/U/V Bigarrays + `pool_stubs.c`), test_decompress (Bigstringaf), devkit_gzip (`z_stream`, `zlibstubs.c:61`), pplacer (GSL Vector/Matrix, sqlite3 handles) | — |
| **explicit `Gc.finalise`** | `caml_final_register` from user OCaml | pplacer (`gsl-ocaml/src/sum.ml`, `rng.ml`, `odeiv.ml`, `eigen.ml`, `integration.ml`) | merlin_bench (`mreader_extend.ml:52`, not the query path) |
| **`Bigarray` allocation** | `caml_ba_alloc` (custom block + off-heap bytes) | owl_gc (dim×dim Float64 Array2; Knob A `OWL_MATRIX_DIM` scales it 100→2400, RSS 26MB→4.77GB), liq_video_frames_pool (1280×720 YUV420), test_decompress (Bigstringaf), ocamlc_self_compile (`emitcode.ml:53` emit buffer) | — |
| **off-heap accounting / `custom_major_ratio` (M)** | `caml_alloc_custom_mem` → pacer | liq_video_frames_pool (the only bench whose wall+RSS Pareto front moves with M — the #14533 repro); owl_gc_{large,huge} (dim 1500/2400 → 18/46 MB Bigarrays, big enough to move the pacer — the Knob-A ladder now reaches this regime) | owl_gc (dim 100, ~80 KB blocks), zarith_pi, test_decompress (custom blocks too small to swing pacer policy) |
| **ephemeron GC machinery** (alloc + per-domain ephe list + `caml_ephe_clean` key scan) | `caml_ephe_create`, `caml_ephe_clean` | alt_ergo_{fill,yyll,unsat_smt2}, frama_c_eva_*, goblint — via `Weak.Make`. `Weak.*` is not a separate path: `runtime/weak.c` routes `caml_weak_*` through `caml_ephe_*` (a weak array is an ephemeron with no data field), so these drive ephemeron alloc + key-cleaning on the hot path (the path that regressed on OCaml 5, #11733). | — |
| **ephemeron *data-field*** (`Ephemeron.K1`-with-data) | `caml_ephe_set_data`/`get_data` + data branch of `caml_ephe_clean` | — (**verified gap, narrowed**) | merlin_bench `saved_parts.ml:3` (cold, disabled), coq `clib/cEphemeron.ml` (VM backend, unreached). No bench sets a data field hot. |
| **`Weak.Make` / weak hashsets** | `caml_ephe_*` | frama_c_eva_sqlite{,_small,_default,_large} (CIL AST + EVA state via `State_builder.Hashconsing_tbl_weak`, largest weak workload; the `-eva-precision` ladder scales it 457→695MB RSS / 11k→182k minor GC), alt_ergo_{fill,yyll,unsat_smt2} (`hconsing.ml:51`), goblint (CIL hash-consing) | — |
| **`Marshal.{to,from}_*`** | `caml_output_value*` / `caml_input_value*` | ocamlc_self_compile (`.cmi` `cmi_format.ml:87`; `.cmo` `emitcode.ml:33`) | liquidsoap-lang (`cache.ml:75`, off by default), jsoo (`parse_bytecode.ml:462`, one-shot), coq (`nativevalues.ml`, native backend unused), merlin `persistent_env` (cold), alt-ergo (`satml.ml:2206`, commented out) |
| **`Effect.perform` (OCaml 5)** | `caml_perform_*`, deep `try_with` | eio_fiber_stream (`suspend.ml:6`, `fiber.ml:11`, `cancel.ml`) | lavyek_kv_*d (disabled), merlin_bench cancellation (disabled) |
| **`Domain.spawn` / `join`** | `caml_domain_*` | — (**gap**: only lavyek_kv_{2,4,8}d and merlin_bench, both disabled) | lavyek_kv_{2,4,8}d, merlin_bench when re-enabled |
| **`Atomic.*` (hot)** | `caml_atomic_*` | eio_fiber_stream (`sem_state.ml`, `lazy.ml`) | lavyek_kv_*d (disabled), merlin_bench (disabled); ocaml-re does Atomic only at regex compile time, so devkit_* see it only in init |
| **kcas / lock-free MCAS** | n/a (library) | — (**verified gap**: lavyek imports `kcas`/`kcas_data` but never calls them; `REMOVED.md:22`) | — |
| **`Sys.set_signal`** | `caml_install_signal_handler` | alt_ergo_unsat_smt2 (`--timelimit 15` arms SIGVTALRM, `signals_profiling.ml:32`) | alt_ergo_{fill,yyll} (handlers installed, never fire); coq SIGINT unused. No high-frequency signal delivery. |
| **`Lazy.force` (hot)** | `caml_call_lazy` | liq_parse_typecheck (`typechecking.ml:386`), jsoo (`inline.ml:195,429,714`), menhir_* (`invariant.ml`) | many cold init lazies |
| **`Format` (hot)** | `Format.{fprintf,pp_*}` | menhir_* (codegen + table dumps), ocamlformat_rocq (whole workload), liq_parse_typecheck (type printing), alt_ergo_*, zarith_pi (`Z.output`) | others use Format only on error paths |
| **`Hashtbl` at scale** | `caml_hash` | menhir_* (`LRijkstraClassic.ml:849`), ocamlc_self_compile (`btype.ml:46 TypeHash`), alt_ergo_*, cpdf_* (`camlpdf/pdf.ml:118`), irmin_mem_rw (`irmin_mem.ml:44`), liq_parse_typecheck (`repr.ml`), pplacer (`ptree.ml:4`), devkit_*, goblint | others touch Hashtbl only trivially |
| **Lwt promises** | `Lwt.bind` continuations | irmin_mem_rw (every store op) | — |
| **Eio fibers (effects layer)** | `Eio.Fiber.*`, `Eio.Stream`, `Eio.Switch` | eio_fiber_stream | lavyek_kv_*d (disabled) |
| **io_uring (real syscalls)** | `Uring.t` via `eio_linux` | — (**gap**: only lavyek_kv_*d, disabled) | lavyek_kv_*d when re-enabled; eio_fiber_stream is pure in-memory (no io_uring) |
| **CPU pinning** | `pthread_setaffinity_np` via `ocaml-processor` | — (**gap**: only lavyek_kv_*d, disabled) | lavyek_kv_*d (`lavyek_bench.ml:59`) when re-enabled |
| **OpenBLAS / GMP / GSL / sqlite3 / zlib C stubs in inner loop** | bulk FFI | owl_gc (OpenBLAS), zarith_pi (GMP), pplacer (GSL+sqlite3), devkit_gzip (zlib), goblint (apron/GMP) | test_decompress is pure-OCaml zlib (FFI-free counterpart) |
| **`Gc.compact` / `Gc.full_major` forced** | `caml_compact_heap`, `caml_finish_major_cycle` | — (**verified gap**) | eio `bench/` calls `Gc.full_major` outside the hot path |
| **`Gc.alarm` callbacks** | alarm register | — (**verified gap**) | — |

### Per-benchmark tag summary (reverse index, hot-path tags only)

| Benchmark | Hot-path tags |
|---|---|
| `coqc_corelib_stress{,_tree_small,_tree_default,_tree_large}` | minor-gc, constructor-alloc; Knob A = numeral/make_tree depth → minor-GC-saturation ladder (RSS 0.57→1.89GB, gc% 90→97% = highest in suite) |
| `eio_fiber_stream` | effects, atomics, eio-fibers, major-promotion |
| `merlin_bench` *(disabled)* | domains, effects, atomics, hashtbl, format; cold: ephemerons, Gc.finalise |
| `lavyek_kv_1d` *(disabled)* | atomics, effects, eio-fibers, io-uring, pthread-affinity, hashtbl |
| `lavyek_kv_{2,4,8}d` *(disabled)* | domains, atomics, effects, eio-fibers, io-uring, pthread-affinity, hashtbl |
| `liq_parse_typecheck{,_small,_default,_large}` | hashtbl, lazy, format, major-promotion, minor-gc; Knob A = script size (argv.2 = generated unit count, in-process) → promotion-heavy AST+type-env ladder (RSS 0.26→0.72GB, ~60% gc%, super-quadratic wall) |
| `ydump_repeat{,_small,_default,_large}` | minor-gc, major-promotion, recursive-variants; Knob A = doc size (argv.2 = generated record count, in-process) → promotion-heavy footprint ladder (RSS 3.25→20GB), 424ms max pause (largest in suite) |
| `test_decompress{,_small,_default,_large}` | bigarray, custom-block-finalisation (Bigstringaf), major-promotion; Knob A = payload size (argv.2) → compute+Bigstring footprint ladder (RSS 0.5→5.7GB), gc% ~0.8% (compute-bound control) |
| `pplacer_testsuite` | Gc.finalise, custom-block-finalisation (GSL+sqlite3), ffi-stubs, hashtbl, minor-gc |
| `pplacer_like_{small,default,large}` | Knob A = likelihood n_sites (like_bench.ml: Felsenstein pruning + 40-pt ML pendant scan over GSL Glv). Off-heap footprint: top_heap ~2-8MB while RSS 0.22→2.18GB, allocated_words 2.1→22.4G, minor 8k→86k, major 147→646. gc%~0.6 flat (compute-bound, promo~0) — the suite's compute-bound/off-heap corner, read by RSS/alloc_words like owl |
| `owl_gc{,_small,_default,_large,_huge}` | bigarray, custom-block-finalisation (Array2), ffi-stubs (OpenBLAS), minor-gc; Knob A = matrix dim (`OWL_MATRIX_DIM`, 2nd wrapper arg) → off-heap footprint ladder (RSS 95MB→4.77GB); large/huge also hit off-heap-accounting pacer |
| `liq_video_frames_pool{,_small,_default,_large}` | bigarray, custom-block-finalisation, off-heap accounting (M-sweep); Knob A = frame resolution (argv.2/3) → major-GC-pacing ladder (majorGC 1104→16837 @ 1080p→8K, gc% ~80-95%, RSS flat) |
| `zarith_pi` | custom-block-finalisation (`Z.t`), ffi-stubs (GMP), minor-gc, format(cold) |
| `devkit_gzip` | custom-block-finalisation (z_stream), ffi-stubs (zlib), hashtbl, buffer |
| `devkit_stre` | hashtbl, minor-gc, buffer, string-allocator |
| `devkit_network` | hashtbl, int32-boxing, minor-gc |
| `devkit_htmlstream` | hashtbl, buffer, minor-gc |
| `sedlex_tokenize{,_small,_default,_large}` | bytes, ppx-match, string-allocator, minor-gc; Knob A = input size (argv.1 # lines) → retained-token-list footprint ladder (RSS 2.7→27GB), gc% RISES 43→61%, 153ms max pause (steepest in suite) |
| `ocamlformat_rocq{,_small,_default,_large}` | format, buffer, minor-gc; Knob A = source size (# lines, generated N× workload.ml) → live-AST footprint ladder (RSS 0.6→8.4GB), constant ~30% gc% + growing major-GC scan pauses (90ms @ large) |
| `cpdf_{merge,blacktext,scale,squeeze}` | hashtbl (object map), bytes mutation, minor-gc; camlpdf C stubs (flate/zlib, AES, SHA-2) hit when decoding/re-compressing streams (squeeze), otherwise pure OCaml |
| `cpdf_squeeze_{small,default,large}` | Knob A = document working set (merge N=8/24/64 copies + recompress). Live PDF object map grows ~linearly with N (top_heap 110→405M w, RSS 0.88→3.0GB, majorGC 38→56); gc% FALLS 31→16% as flate C recompression dominates. Live-heap ladder, not a GC-pacing one |
| `alt_ergo_fill, alt_ergo_yyll` | weak-refs (Weak.Make hash-consing), hashtbl, format |
| `alt_ergo_chain_{small,default,large}` | Knob A = single-solve problem size (generated chain VC a(0)=0, a(i)=a(i-1)+1, prove a(N)=N; N=4000/7000/10500). One large mostly-live congruence structure per solve: top_heap 76→638M w, RSS 0.6→4.9GB, minor 3.7k→25k (major only 16→24, promo ~0.1). gc% RISES 14→26%, pauses grow (p99.9 3→22ms) — heap-scan-bound. Distinct from fill_x100's Knob-B repetition |
| `alt_ergo_unsat_smt2` | weak-refs, hashtbl, format, signals (SIGVTALRM armed by `--timelimit 15`) |
| `frama_c_eva_{t,sqlite,sqlite_small,sqlite_default,sqlite_large}` | weak-refs / ephemeron-backed hash-consing (Weak.Make at scale), hashtbl, recursive-variants (CIL AST), minor-gc, max-rss (sqlite, #11733). Knob-A ladder = `-eva-precision` (2nd wrapper arg) on sqlite; slevel inert; t is a fixed fast standalone |
| `goblint` | high allocation / minor-gc churn (~1.3GB for a 5.6KB input), hash-consing, apron relational domains (C/GMP FFI), recursive-variants (CIL AST), allocated-bytes (#13733) |
| `menhir_{sysver,ocamly,sysver_canonical,sql_parser}` | hashtbl, format, lazy, minor-gc; Knob-A ladder (automaton scale) = small sysver--table / default ocaml--canonical / large sysver--canonical, monotone by wall 7.8→13→34s AND RSS 0.72→2.76→4.0GB. sql_parser (LALR 1.2s) = fast extra, not a rung. Single-run (menhir has no loopable main) |
| `ocamlc_self_compile` | hashtbl, marshal (`.cmi`+`.cmo` writeout), bigarray (emit buffer), minor-gc |
| `jsoo{,_small,_default,_large}` | hashtbl, lazy, marshal(cold); Knob A = input bytecode size (rung arg → generated per-runtime .byte from real JSOO sources × R replicas) → whole-program-IR footprint ladder (RSS 0.5→7.8GB), constant ~33% gc% + 129ms max pause @ large |

## Coverage gaps — verified

A regression in any of these areas would **not** be caught by the current suite.
Each was checked by `grep -rn` against the actual vendored source.

- **Multi-domain parallelism (`Domain.spawn`/`join`), real io_uring syscall traffic,
  and per-domain CPU pinning** — gaps because the only benchmarks that exercised them
  are disabled: `lavyek_kv_*` (private repo) covered all three, `merlin_bench` covered
  the 2-domain case. `eio_fiber_stream` still exercises single-domain effects, fibers,
  and Atomic, but nothing drives N>2 domains, io_uring, or affinity pinning. Re-enabling
  lavyek or importing a Sandmark `parallel_*` benchmark would close these.
- **Ephemeron data-field semantics** — verified gap, narrowed. `runtime/weak.c` routes
  `caml_weak_*` through `caml_ephe_*` (a weak array is an ephemeron with no data field),
  so the ephemeron machinery (alloc, per-domain list, `caml_ephe_clean` key-scan) is
  covered on the hot path by the `Weak.Make` workloads: `frama_c_eva_sqlite`, `alt_ergo_*`,
  and now `goblint`. What remains uncovered is only the data-field path (`Ephemeron.K1`
  with data, `caml_ephe_set_data`/`get_data` + the data-clearing branch). No bench sets
  an ephemeron data field hot.
- **kcas / lock-free MCAS** — verified gap. Even when lavyek was enabled it didn't call
  kcas (`REMOVED.md:22`). A small standalone benchmark wrapping `kcas` would close it.
- **Domainslib work-stealing pools** — uncovered (eio uses fibers; lavyek dispatched via
  a manual `Atomic.fetch_and_add` counter).
- **`Gc.compact` / `Gc.full_major` in a hot loop** — no benchmark forces a full GC.
- **`Gc.alarm` / `Gc.create_alarm`** — no benchmark registers one.
- **High-frequency signal delivery in tight loops** — alt-ergo registers handlers but
  they fire at most once per run.
- **Pure-OCaml hot inner-loop float (flambda)** — owl_gc defers to OpenBLAS, so flambda
  has nothing to optimise in the inner loop. A pure-OCaml numerical kernel would catch it.
- **`Bigarray` slicing / reshape patterns** — owl_gc doesn't slice; liq_video_frames_pool
  fills planes without slicing.
- **Polling-points / safe-point density** — nothing stresses cooperative cancellation.
- **Direct user `Effect` handlers (outside Eio)** — every effect-perform goes through Eio.

If a runtime change touches one of these areas, flag the gap explicitly when proposing it.

## Vendored source patches

Applied automatically by `scripts/setup-monorepo.sh`.

| # | Target | What | Why |
|---|--------|------|-----|
| 1 | `duniverse/alt-ergo/.../theories.ml` | Fix ppx_blob paths | ppx_blob resolves from workspace root |
| 2 | `duniverse/alt-ergo/.../text/dune` | Rewrite dune file | Remove public_name/package (vendored exec) |
| 3 | `duniverse/dune_/dune-project` | `3.22` → `3.21`, rm test/ | dune 3.22 features not in installed dune |
| 4 | `duniverse/ppxlib/` | Replace with a pinned commit (`sources.yml`) | Adds Ast_506 for OCaml 5.6 trunk |
| 5 | `duniverse/lwt/` | Replace with a pinned commit (`sources.yml`) | Fixes socketaddr.h for OCaml 5.6 |
| 6 | `duniverse/devkit/lwt_engines.ml` | Add `engine_id` type + method | lwt 6.1.1 added virtual `id` method |
| 7 | `vendor/libevent/libevent.ml` | Add `~persist`, `~signal` labels | OCaml 5.x strict label matching |
| 8 | `duniverse/js_of_ocaml/.../dune` | Remove public_name | Vendored executable |
| 9 | `duniverse/ocamlformat/.../dune` | Remove public_name | Vendored executable |
| 10 | `duniverse/owl/.../exponpow.c` | Fix `std_gaussian_rvs` calls | Upstream C bug: function takes no args |
| 11 | `duniverse/batteries-included/.../batGc.mli` | Add `live_stacks_words` field | OCaml 5.6 added field to `Gc.stat` |
| 12 | `vendor/pplacer/mcl/caml/caml_mcl.c` | Add `#include <stdint.h>` | OCaml 5.6 trunk headers need it |
| 13 | `vendor/pplacer/tests/tests.ml` | Add `PPLACER_TEST_LOOP` env-var loop | Run the suite N times in one process (see Iteration counts) |
| 14 | `duniverse/analyzer/.../runtime/include/goblint.h` | `__goblint_assume_join` arg type | GCC 14+/C23 conflicting-types vs the `.c` definition |
| 15 | `duniverse/cpu/` | Run `autoconf; autoheader; ./configure` **with `$TOOLS_BIN` on `PATH`** | Generates `src/config.h` its C stub needs (opam runs this; dune doesn't). `./configure` probes for `ocamlc` and aborts with "You must install the OCaml compiler" without one, and this patch section runs *before* step [8] puts `$TOOLS_BIN` on `PATH` — so it must set it itself. Failure is fatal: it used to be a swallowed warning, and the only symptom was goblint failing much later with `cpu_stubs.c:1:10: fatal error: config.h: No such file or directory` |
| 16 | `duniverse/json-data-encoding/.../json_repr.{ml,mli}` | Add `` `Tuple ``/`` `Variant `` to `Json_repr.Yojson` | dune-universe fork narrows the type; goblint treats it as `Yojson.Safe.t` both ways |
| 17 | `duniverse/bare-ocaml/src/dune` | Install `Bare_encoding.ml`/`.mli` | catapult copies them via `%{lib:bare_encoding:…}` (needs source installed) |
| 18 | `duniverse/analyzer/.../control.ml` | Annotate `(module CFG : CfgBidirSkip)` | OCaml ≥ 5.5 can't infer the packaged-module signature otherwise |
| 19 | `duniverse/rocq/dune-project` + `dune` | Drop `(using coq 0.8)` and the `dev`-profile `(coq (flags ...))` | dune 3.24 deleted the `coq` extension. It's a *parse* error, so it broke **every** build in the workspace, not just rocq's. Both declarations are dead here (rocq generates its theory rules via `tools/dune_rule_gen`; the only stanzas needing the extension are in `dune.disabled` files), so they're removed rather than ported to `(using rocq ...)` |
| 20 | `duniverse/rocq/toplevel/dune` | Collapse the `(select memtrace_init.ml …)` to its `(-> memtrace_init.default.ml)` default clause | rocq-runtime has an *optional* memtrace integration (`(select)` + `depopts: memtrace`). dune auto-enables it the moment `memtrace` is present anywhere in the workspace — which it is once a benchmark vendors memtrace — so `rocq-runtime.toplevel` gains `requires memtrace` in its generated META. The rocq bootstrap's `gen_rules.exe` resolves that library through findlib on `$OCAMLPATH`, where the vendored memtrace is never installed, and dies with `findlib error: memtrace not found … required by rocq-runtime.toplevel`. Forcing the default (memtrace-free) clause keeps rocq's toplevel from ever linking/requiring memtrace, independent of any benchmark vendoring it |

## Known limitations

- **Rocq symlink**: setup creates a symlink at
  `<parent_of_monorepo>/install/default/lib/rocq-runtime` pointing at `_rocq_prefix/`,
  because dune's generated `.vo` rules use relative paths that resolve outside the
  monorepo. `make clean-all` removes it.
- **melange**: parked. Needs the `(using melange 0.1)` dune extension; can't benchmark
  standalone.
- **Frama-C / dune-site**: EVA is linked statically (`-linkall`) and run with
  `-no-autoload-plugins`, so dune-site plugin discovery is never used (the `.cmxs` path
  doesn't work for a relocated, uninstalled build). Its resource sites are empty in an
  uninstalled build, so `frama-c.build.sh` sets `DUNE_DIR_LOCATIONS` at `vendor/frama-c`.
  WP is excluded (its `why3` dep caps OCaml < 5.5); EVA needs neither.
- **goblint / apron**: apron is non-dune (configure/make + camlidl), so it can't join the
  unified dune build. `scripts/vendor-apron.sh` builds the camlidl/mlgmpidl/apron chain
  per-runtime from pinned source into a self-contained prefix (opam-free: active compiler
  + gcc + ocamlfind + make), and `goblint.build.sh` exposes it via `OCAMLPATH`. Runtime
  stubs are found via `pre.custom_includes` since dune-site sites aren't populated in an
  uninstalled build. On trunk goblint builds from `fb4f451` onward (the late-May
  `cfb30145` snapshot hit a since-fixed `Ctype.Unify` compiler bug).
- **OxCaml**: only menhir, test_decompress, and zarith_pi work; others fail on
  locality-type annotation errors in vendored packages.
- **Trunk (5.6) support**: depends on ppxlib and lwt git main (patches 4+5). When ppxlib
  releases a 5.6-compatible version, these can be dropped and the lock file updated.
- **pplacer**: vendored manually (not in opam); needs `libgsl-dev` and `libsqlite3-dev`.
- **frama-c**: vendored manually (`scripts/vendor-frama-c.sh`); 32.1 isn't in opam and only
  a trimmed kernel+EVA is built. Needs `libyaml`/`pkg-config` and a C preprocessor. The
  vendor script fills Frama-C's empty `*.opam` placeholders so opam-monorepo can scan.

## Updating dependencies

For a third-party source that is **not** in the lock file (the git pins and the
tarballs — ppxlib, lwt, js_of_ocaml, pplacer, mcl, frama-c, the apron chain, cpdf,
menhir, rocq, alt-ergo's deps, …), the bump is a one-line edit to `sources.yml`
followed by `make setup`. Nothing else references the version.

For the lock file itself:

```bash
# 1. Modify dune-project if adding/removing packages
# 2. Re-lock in a switch that has the opam-monorepo plugin
#    (OPAMSWITCH selects it for this one command without changing your shell's switch)
OPAMSWITCH=<tools-switch> opam monorepo lock
# 3. Rebuild from scratch
make clean-all && make setup
# 4. Commit the updated lock file
git add macro-benches.opam.locked dune-project *.opam
git commit -m "Update vendored dependencies"
```

## Adding a new benchmark

1. Add a `(package ...)` declaration in `dune-project`.
2. Create an `.opam.template` if non-dune deps need `x-opam-monorepo-opam-provided`.
3. Re-lock: `opam monorepo lock`.
4. Create `benchmarks/<tool>/` with `<tool>.build.sh`, a `dune` file (if custom `.ml`),
   and input files.
5. Add every program to `benchmarks/manifest.yml` **in the same commit** — CI fails
   if a build script has no program entry (or vice versa). For a Knob-A ladder, list
   only the `_small` rung. A tool that ships disabled goes under `disabled:` with a
   reason instead.
6. Register it in your orchestrator config (running-ng's experiment YAML), with the
   same `args` string as the manifest.
7. Add it to the test-build list in `scripts/setup-monorepo.sh`.
8. Add a human page at `docs/benchmarks/<tool>.md`.
9. Test: `make clean-all && make setup`, then
   `ONLY="<prog>" bash scripts/ci-build-all.sh && ONLY="<prog>" bash scripts/ci-run-all.sh`.

---

## Backlog

Follow-up benchmarking work carried over from the old `TODO.md`. Append entries with
date, owner if known, and enough context that someone else can pick it up. The
coverage-gaps section above is the current authority on what the suite misses; the
first entry here is the prioritised plan for closing those gaps.

### Close runtime-feature coverage gaps — filed 2026-05-15

A source-grounded audit of every benchmark against the runtime mechanisms it exercises
turned up ten mechanisms no benchmark exercises hot (see "Coverage gaps" above). The
running-ng `RUNNING_TAG=ephemerons` and `RUNNING_TAG=kcas` selectors already error
loudly when invoked, which keeps those two discoverable; the rest live only in docs.

Since filing, frama-c and goblint landed and cover the **ephemeron machinery** on the
hot path via `Weak.Make`, so gap #1 has narrowed to the ephemeron **data-field** path
only. The remaining gaps and candidate closures:

- Ephemeron data-field (`Ephemeron.K1.Hashtbl`): small dedicated benchmark, ~100-200 lines.
- kcas / lock-free MCAS: standalone benchmark wrapping `Kcas_data.Hashtbl`/`Queue` under
  N-domain contention, ~150 lines; can vendor as a sibling to lavyek.
- Domainslib work-stealing: Sandmark `parallel_binarytrees` import (~200 lines).
- Forced `Gc.compact`/`Gc.full_major`: a `_compact` variant wrapping an existing
  allocation-heavy driver (compaction-vs-finalisers is the interesting story for owl_gc
  and liq_video_frames_pool).
- `Gc.alarm` callbacks: synthetic ~50-line driver.
- High-frequency `Sys.set_signal`: itimer-driven SIGALRM at ~1ms combined with an
  allocator-heavy driver.
- Pure-OCaml flambda-sensitive float kernel: Sandmark `nbody`/`raytracer`/`mandelbrot`
  import (~200 lines each; `nbody` is the canonical flambda one).
- `Bigarray` slicing/reshape: a `Genarray.slice_left`/`Array1.sub` micro-stressor, or
  fork owl_gc to slice-based access.
- Polling-points / safe-point density: tight no-alloc loop under an `Eio.Switch` with
  periodic cancellation pokes.
- Direct user `Effect.Deep.try_with` outside Eio: Sandmark `effects` microbench (~80 lines).

Suggested order, cheapest signal first: `Gc.alarm` synthetic → `Gc.compact` variant →
Sandmark `nbody` → ephemeron data-field synthetic → kcas synthetic → Sandmark
`parallel_binarytrees`. Status: not started.

### Investigate `ocamlc_self_compile` allocation regression on d8b — filed 2026-05-06

`ocamlc_self_compile` regresses ~+8% wall on d8bb46c across all flag combos but only drops
~5% RSS, unlike sibling RSS-winners (cpdf_*, menhir_sysver) that drop 20-40% RSS. On the
2026-05-03 monolith N=3 run, d8b allocates ~1.3 GB more minor-heap bytes for the same
deterministic compile (8.57 → 9.90 GB total, minor collections +15.6%, major −25%, RSS
−4.9%). By contrast cpdf_merge's total allocation is identical across versions and only RSS
moves (the canonical pacer story). So this is the workload allocating differently between
versions, not the pacer.

The old ephemeron hypothesis was **invalidated 2026-05-15**: `grep -rn Ephemeron typing/
bytecomp/ driver/ utils/` returns nothing in 5.4.1 and trunk; `btype.ml:46` uses
`Hashtbl.Make`. Leading hypotheses now: stdlib growth (more modules to typecheck per
compile), `Hashtbl` resize/per-entry overhead in `TypeHash`, `Marshal`/`Compression`
buffer behaviour for `.cmi`/`.cmo`, or the `Bigarray.Array1` emit-buffer growth policy.
Next steps: `OCAMLRUNPARAM=v=0x400` per-cycle GC log to see when the extra allocation lands;
reduce the workload to one module to test per-node vs fixed offset; statmemprof diff; bisect
5.4 → d8b. Status: not started.

### Domainslib / work-stealing N-domain benchmark — filed 2026-05-01, updated 2026-05-15

Lavyek (when enabled) provided N>2 domain shared-heap GC under contention plus io_uring, so
the remaining gap is specifically **work-stealing scheduler load**: nothing consumes
`Domainslib.Task.{run,parallel_for,async}`. Options: Sandmark `parallel_binarytrees` import
(preferred, ~200 lines, established shape), a synthetic tree-of-tasks driver under
`Domainslib.Task` (~150 lines), or Meta's `infer` (largest; open questions on
opam/dune-buildability and work-distribution pattern). Status: open; overlaps the
coverage-gaps entry.

### Re-enable `merlin_bench` once the upstream race is fixed — filed 2026-05-01

`merlin_bench` is vendored from the merlin-domains branch (PR #1890) and is the only
2-domain steady-state workload (main + typer worker). It's disabled: the typer-domain
handoff has a non-deterministic race that fires `Types.rev_log → Invalid -> assert false`
at N≥2 iterations on both 5.4.1 and d8bb46c. Full repro in
`benchmarks/merlin/UPSTREAM_BUG.md`. When picking up: watch PR #1890, re-vendor, flip the
programs list back on in running-ng, and re-validate (7 cram queries, ~16s at arg=4, ~1 GB
RSS, ~24% gc_overhead). Re-enabling moves `domains`/`effects`/`atomics` tags from cold to
exercised. Status: waiting on upstream fix.

### GC-parameter sweep on `liq_video_frames_pool` and related — filed 2026-05-01

Steps 1-2 resolved 2026-05-14: on the real liquidsoap pipeline (Ryzen 9 9950X), `M=250`
trades +10% RSS for −17% CPU, the predicted #14533 free-lunch shape in the large-M regime
(repro in the `offheap_M_o_sweep_2026_05_13.yml` results). Still pending: extend the sweep
to one bench per allocation-profile bucket (owl_gc, zarith_pi, liq_parse_typecheck,
ocamlc_self_compile — the last re-characterised 2026-05-15 as minor-heavy Hashtbl + Marshal
+ Bigarray, not ephemeron), then re-run the 8-variant cross-runtime comparison with each
bench at its per-runtime optimal `(s, o)` to see whether the apparent `zarith_pi` (16%) and
`ocamlc_self_compile` (10%) regressions shrink. Tooling: the `gc_sweep_all_versions.yml` and
`offheap_M_o_sweep_*.yml` running-ng configs. Status: steps 3-4 pending.
