# pplacer

pplacer is a phylogenetics tool: it places sequences onto a reference
evolutionary tree. This benchmark runs pplacer's own OUnit test suite, which
builds phylogenetic trees, runs numerical work through GSL, and stores
intermediate state in sqlite3. It is a mixed FFI-plus-tree-allocation
workload, and one of the heaviest GC-overhead benchmarks in the suite.

## What it runs

The build script builds `vendor/pplacer/tests.exe` from the manually vendored
pplacer source and wraps it. The test entry point
(`vendor/pplacer/tests/tests.ml`) runs four sub-suites: guppy, pplacer, rppr,
and json (about 224 tests in total, per the README).

To scale wall time while keeping a single observable OCaml process, the entry
point reads the `PPLACER_TEST_LOOP` env var (default 1) and runs the whole
suite that many times. It uses an env var rather than `Sys.argv` on purpose,
so it does not collide with OUnit's own argument parsing (`-only-test`,
`-verbose`, and so on). Correctness is only checked on the first pass;
later passes are purely for wall-time scaling, because at least one test
(`guppy:gaussian:coastal.v.upwelling`) leaks state between runs and would
report a false failure on repeat.

The wrapper `cd`s into `vendor/pplacer` first, because the tests reference
`./tests/data/` by relative path, then sets `PPLACER_TEST_LOOP` from the
runner's first arg and `exec`s the test binary. The suite typically runs at
arg=5.

## Knob-A ladder (likelihood alignment length)

`pplacer_testsuite` scales by *repetition* (the OUnit suite looped in-process —
Knob B, fixed data). The `pplacer_like_{small,default,large}` rungs scale a real
working set instead. `like_bench.ml` lifts pplacer's Felsenstein likelihood hot
path out of `tests/pplacer/test_like.ml` (the same code copied from
`pplacer_run.ml`, minus its exact-value assertion): it builds the generalized
likelihood vectors (Glv) over a reference tree and computes attachment
likelihoods. Knob A is **n_sites** (alignment length), scaled by replicating the
reference alignment's columns (`PPLACER_LIKE_MULT`, the single arg): the Glv are
GSL-backed **off-heap** `Bigarray`s sized by n_sites, so a bigger alignment grows
the off-heap working set linearly. Each edge runs a fixed 40-point ML
pendant-branch-length scan (what placement actually does to attach a query),
which is the compute that lifts wall into owl-like bands rather than the
~1.7 s/GB of a single pass. Measured on OCaml 5.5.0, Ryzen 9 9950X
(`fingerprint.sh` `v=0x400`; olly from `perf_grp1|re-25|md-2`):

| rung | mult | sites | wall | gc% | RSS | top_heap | allocated | minor GC | major GC |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `_small` | 8 | 17.6k | 4.7s | 0.6% | 0.22 GB | 1.9 MB | 2.1 G w | 8249 | 147 |
| `_default` | 25 | 55k | 14.9s | 0.6% | 0.65 GB | 3.0 MB | 6.6 G w | 25363 | 257 |
| `_large` | 85 | 187k | 50.6s | 0.6% | 2.18 GB | 8.4 MB | 22.4 G w | 85834 | 646 |

This is the suite's **off-heap-footprint, compute-bound** corner. `top_heap` stays
~2-8 MB while RSS spans 0.2-2.2 GB — the working set is ~99.6% GSL off-heap
`Bigarray`, and promotion is ~0, so gc% is a flat ~0.6% and pauses are sub-ms:
almost all the time is in the GSL matrix-vector likelihood, not the collector.
Read this ladder by **RSS and allocated_words** (2.1 → 22.4 G words), not
`top_heap` — the off-heap caveat, same as owl, but on real Felsenstein pruning.
It complements owl's Bigarray-matrix ladder (which carries more GC from
finalisation) and contrasts every other Knob-A ladder, which are GC-bound. The
per-edge scan count (40) is held fixed across rungs; only n_sites varies. A huge
band is deferred (mult ~250 would be ~min-scale at ~6 GB).

## What it stresses

- Explicit `Gc.finalise`. The GSL bindings register finalisers from OCaml
  (in `sum.ml`, `rng.ml`, and others), which is unusual in this suite.
- Custom-block finalisation for GSL vectors/matrices and sqlite3 statement
  handles.
- GSL and sqlite3 C stubs (numerical work and an in-memory database for the
  tests).
- Tree and node allocation in pure OCaml (phylogenetic trees are recursive
  types), plus polymorphic `compare` on that tree-structured data and
  `Hashtbl` use in the tree code.

## Reading the results

Expect wall time around 13s at arg=5, with GC overhead near 70% (the top
tier of the suite) and RSS around 70 MB. Allocation is promotion-heavy,
roughly a third of minor collections carrying a major step.

Because it mixes FFI and tree allocation, movement here that also shows up in
owl points at the FFI or numerical-codegen path; movement that tracks a
tree/AST-allocation benchmark instead points at the tree side; movement on
its own points at the GSL or sqlite3 wrappers specifically.

## Notes

- Vendored manually (not via opam-monorepo), and needs pre-built C libraries:
  libgsl-dev and sqlite3, plus the bundled mcl in `vendor/pplacer/mcl/`.
- It does not build on the gc-pacing runtimes (there are
  `.build-failed` markers for those in the benchmark directory), so it is
  absent from gc-pacing comparisons.
- Under ocaml-mmtk it builds but crashes at run with SIGABRT (a channel
  finaliser locks an already-closed channel), so exclude it from mmtk sweeps.
