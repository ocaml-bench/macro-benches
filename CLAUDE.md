# CLAUDE.md — working notes for agents & contributors on `macro-benches`

Auto-loaded context for Claude Code (and a quick orientation for humans). Keep it
short and current.

## What this is

- A **dune monorepo** of real-world OCaml programs used as macro-benchmarks (coq,
  frama-c, alt-ergo, goblint, menhir, cpdf, owl, jsoo, irmin, liquidsoap, ocamlformat,
  decompress, eio, sedlex, yojson, zarith, pplacer, devkit, …). All third-party deps
  are **vendored** under `duniverse/` (opam-monorepo), so every runtime compiles
  byte-identical source.
- Driven by `~/running-ng` (suite type `OCamlBenchmarkSuite`, **not** the
  satellite-switch path): each benchmark has `benchmarks/<tool>/<tool>.build.sh` that
  runs `dune build` with the runtime compiler on PATH, into a **per-runtime build dir**
  `_build-<runtime>`, then copies/links out the binary `benchmarks/<tool>/<prog>-<runtime>`.

## Hard rules (do not violate)

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
- Keep documentation files (eg. README.md) consistent with every commit. 


## Where things live (read first)

- `benchmarks/<tool>/` — `<tool>.build.sh` (called by running-ng) + input data.
- `duniverse/` — vendored dependency sources (the actual compiled code).
- `vendor/` — manually vendored bits (camlpdf, cpdf-source, zarith, pplacer, …).
- `scripts/` — `setup-monorepo.sh`, `vendor-*.sh` (coq, apron, frama-c, cpdf, …).
- `sources.yml`, `macro-bench-*.opam(.template)`, `dune-workspace`, `dune-overlays`.
- `_build-<runtime>/` — per-runtime dune build output (gitignored).

## Build / run

- running-ng calls `<tool>.build.sh` with the runtime compiler on PATH and these env
  vars: `RUNNING_OCAML_OUTPUT` (where to put the binary), `RUNNING_OCAML_BENCH_DIR`,
  `RUNNING_OCAML_RUNTIME_NAME`, `RUNNING_OCAML_SWITCH`. Scripts `unset` opam/OCAML env
  vars to avoid cross-runtime `.cmi` contamination, then `dune build --root <monorepo>
  --build-dir _build-<runtime> --profile release <target>` and copy the result out.
- Standalone usage (no running-ng): set `RUNNING_MACRO_BENCH_DIR=~/macro-benches` and
  drive `~/running-ng`'s `build_ocaml_binaries_gc_sweep.sh` / `run_ocaml_bench_gc_sweep.sh`.

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
  5.5.0-rc1, ocaml-mmtk). All 31 programs build on stock 5.5.0-rc1.
- **External C deps:** apron (goblint) needs camlidl; owl needs openblas/cblas; cpdf
  needs camlpdf; these come via `vendor/` + `scripts/vendor-*.sh`.
- **Under ocaml-mmtk** (built via running-ng's `OCamlMMTk`): all 31 *build* (the
  runtime supplies `LIBRARY_PATH`+heap), but a few **crash at run** — alt-ergo
  (SIGSEGV, moving-GC) and pplacer (SIGABRT, channel-finalizer) — see the
  ocaml-mmtk issues; exclude them from minheap/sweeps.

## Per-session workflow

1. Identify which benchmark/tool you're touching; its build glue is
   `benchmarks/<tool>/<tool>.build.sh`; its source is under `duniverse/` or `vendor/`.
2. Build via running-ng with `RUNNING_MACRO_BENCH_DIR` set; don't hand-delete `_build`
   internals.
3. Commit only when asked; `Co-Authored-By: Claude` is fine; don't commit build output.
