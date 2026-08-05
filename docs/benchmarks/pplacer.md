# pplacer

pplacer is a phylogenetics tool that places sequences onto a reference
evolutionary tree. The ladder lifts pplacer's Felsenstein likelihood hot path
(`like_bench.ml`, from `tests/pplacer/test_like.ml`): it builds the generalized
likelihood vectors (Glv) over a reference tree and computes attachment
likelihoods, with each edge running a fixed 40-point ML pendant-branch-length
scan — a mixed FFI-plus-tree workload dominated by GSL matrix-vector compute.

## Ladder

The ladder scales **n_sites** (alignment length, via `PPLACER_LIKE_MULT`) by
replicating the reference alignment's columns. The Glv are GSL-backed **off-heap**
`Bigarray`s sized by n_sites, so a bigger alignment grows the off-heap working set
linearly; the per-edge scan count (40) is held fixed across rungs. Measured on
OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly from
`perf_grp1|re-25|md-2`):

| rung | mult | sites | wall | RSS | allocated | gc% |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 8 | 17.6k | 4.7s | 0.22 GB | 2.1 G w | 0.6% |
| `_default` | 25 | 55k | 14.9s | 0.65 GB | 6.6 G w | 0.6% |
| `_large` | 85 | 187k | 50.6s | 2.18 GB | 22.4 G w | 0.6% |

This is the suite's **off-heap-footprint, compute-bound** corner. `top_heap` stays
~2-8 MB while RSS spans 0.2-2.2 GB — the working set is ~99.6 % GSL off-heap
`Bigarray`, promotion is ~0, so gc% is a flat ~0.6 % and pauses are sub-ms: almost
all the time is in the GSL likelihood, not the collector. Read this ladder by
**RSS and allocated_words** (2.1 → 22.4 G), not `top_heap` — the off-heap caveat,
same as owl, but on real Felsenstein pruning (owl carries more GC from
finalisation; every other ladder is GC-bound). A huge band is deferred (mult ~250
≈ min-scale at ~6 GB).

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `pplacer_testsuite` — the original OUnit test-suite bench (guppy/pplacer/rppr/
  json, ~224 tests) looped in-process via `PPLACER_TEST_LOOP` (fixed data, scaled
  by repetition; runs at arg=5, ~70 % gc%).

## Notes

- Vendored manually (not via opam-monorepo); needs pre-built C libraries
  (libgsl-dev, sqlite3) plus the bundled mcl in `vendor/pplacer/mcl/`.
- Does not build on the gc-pacing runtimes (`.build-failed` markers), so it is
  absent from gc-pacing comparisons.
- Under ocaml-mmtk it builds but crashes at run with SIGABRT (a channel finaliser
  locks an already-closed channel), so exclude it from mmtk sweeps.
