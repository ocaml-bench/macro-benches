# owl

Owl is OCaml's numerical/scientific library; its dense matrix ops dispatch to
OpenBLAS through C stubs. The benchmark drives a Gromov–Wasserstein-style distance
computation over a grid of random matrices, bouncing between the OCaml heap,
off-heap `Bigarray` data, and BLAS, so it stresses `Bigarray` allocation/finalisation
(each `Mat.dot` frees off-heap float data via a finaliser) and stub-call overhead.

## Ladder

Input size = the **matrix dimension** (`OWL_MATRIX_DIM`); the off-heap `Bigarray`
live set is `100 · dim² · 8` bytes, so RSS grows ~quadratically and each rung
reaches a footprint regime the one below did not. Measured on 5.5.0, Ryzen 9 9950X,
OpenBLAS single-threaded:

| rung | dim | wall | RSS | gc% | max pause |
| --- | --- | --- | --- | --- | --- |
| small | 250 | 4.7s | 102 MB | 18% | 0.07 ms |
| default | 400 | 15s | 182 MB | 6% | 0.10 ms |
| large | 800 | 98s | 573 MB | 2% | 0.71 ms |

Read this ladder by **RSS**, not `top_heap_words` (flat, since the bulk data is
off-heap). BLAS work grows with dim³ and GC work with dim², so gc% falls as the rungs
grow: `_small` is the GC-throughput rung, `_large` the off-heap footprint rung. Pauses
stay under 1 ms on every rung.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `owl_gc`: the original repetition bench (loop 6, dim 100, ~4s); fixed working
  set, more samples of one regime.

## Notes

- Needs OpenBLAS / cblas at build time.
- The wrapper sets `OPENBLAS_NUM_THREADS=1` unless it is already set. OpenBLAS
  otherwise starts one thread per core, which makes wall time depend on the machine
  and on CPU pinning rather than on the OCaml runtime.
- The output is a wrapper script, not a copied binary: if you wipe the build dir,
  delete the wrapper output too so running-ng regenerates the `.exe`.
