# owl

Owl is OCaml's numerical/scientific library; its dense matrix ops dispatch to
OpenBLAS through C stubs. The benchmark drives a Gromov–Wasserstein-style distance
computation over a grid of random matrices, bouncing between the OCaml heap,
off-heap `Bigarray` data, and BLAS — so it stresses `Bigarray` allocation/finalisation
(each `Mat.dot` frees off-heap float data via a finaliser) and stub-call overhead.

## Ladder

Input size = the **matrix dimension** (`OWL_MATRIX_DIM`); the off-heap `Bigarray`
live set is `100 · dim² · 8` bytes, so RSS grows ~quadratically and each rung
reaches a footprint regime the one below did not. Measured on 5.5.0, Ryzen 9 9950X:

| rung | dim | wall | RSS | gc% | max pause |
| --- | --- | --- | --- | --- | --- |
| small | 300 | 4.0s | 95 MB | 24% | 1.6 ms |
| default | 500 | 11s | 230 MB | 11% | 3.4 ms |
| large | 1500 | 124s | 1.9 GB | 8% | 27 ms |
| huge | 2400 | 453s | 4.77 GB | 8% | 53 ms |

Read this ladder by **RSS**, not `top_heap_words` (flat — the bulk data is off-heap).
`_small` is GC-throughput-heavy (24% gc%); `_large`/`_huge` are GC-latency benches —
the steepest pauses in the suite (27→53 ms) as the collector scans/finalises multi-GB
of off-heap custom blocks, and big enough to move the `custom_major_ratio` pacer. Wall
is BLAS-thread-bound (less stable across machines than RSS).

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `owl_gc` — the original repetition bench (loop 6, dim 100, ~16s); fixed working
  set, more samples of one regime.

## Notes

- Needs OpenBLAS / cblas at build time.
- The output is a wrapper script, not a copied binary: if you wipe the build dir,
  delete the wrapper output too so running-ng regenerates the `.exe`.
