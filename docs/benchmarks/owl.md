# owl

Owl is OCaml's numerical/scientific computing library. Its dense matrix
operations dispatch to OpenBLAS through C stubs. This benchmark drives Owl
through a Gromov-Wasserstein style distance computation over a grid of random
matrices, so it spends most of its time bouncing between the OCaml heap,
off-heap Bigarray data, and BLAS.

## What it runs

The program is `owl_gc` (`benchmarks/owl/owl_gc.ml`). It builds 100 random
100x100 `Bigarray.Array2` matrices (dimensions `num_sample_pts = 100`,
`dim = 100`), then walks every unordered pair (i, j) and computes a
distance for that pair via `Gw.gw_uniform`. That is 4950 pairs per pass
(the README rounds this to "5000 pair calls").

Each pair call runs a small fixed chain of Owl operations: a couple of
`c_a` cost terms, one `gw_cost` (a Frobenius product built on `Mat.dot` and
`contract2`), and a `uniform_coupling`. Every one of those goes out to
OpenBLAS.

The binary takes one argument, the number of full passes over the grid
(`Sys.argv.(1)`, default 1). The build wrapper passes the runner's arg
through and `exec`s the real `.exe`, so the whole run is a single OCaml
process that olly can observe end to end. The suite typically runs it at
arg=6 on the `re-25` ring.

## What it stresses

- Bigarray allocation and finalisation. Every `Mat.dot` allocates a small
  header block on the OCaml heap whose finaliser frees the off-heap float
  data. With thousands of these per second, the finaliser path is hot.
- OpenBLAS stub calls in the inner loop. The actual arithmetic happens in C,
  so this is a good measure of FFI/stub-call overhead and of Owl's wrapper
  layer between OCaml and BLAS.
- Not much else. The driver is plain imperative loops over int indices with
  no closures of note, and no pure-OCaml float kernel to speak of (the math
  is all in BLAS).

## Reading the results

Expect wall time around 16s at arg=6, with GC overhead near 50% and RSS
around 150 MB. A notable fingerprint is that minor and major collection
counts come out roughly equal: every minor collection tends to carry a
major step, which is the Bigarray-finalisation pattern showing up.

If this regresses on its own (while a pure-allocation benchmark like coq does
not), the runtime's small-allocation fast path is probably fine and the
suspect is the Bigarray finaliser, custom-block dispatch, or stub-call
overhead.

## Notes

- Needs OpenBLAS / cblas at build time.
- The `_build-<runtime>` output is a wrapper script, not a copied binary. If
  you wipe the build dir you must also delete the wrapper output so
  running-ng regenerates the `.exe`, otherwise the wrapper runs and fails
  with `exit 127`.
- Allocation-heavy: at large iteration counts the runtime_events ring can
  overflow, which is why the in-process-loop runs use the larger `re-25`
  ring.
- Source detail worth knowing: `Gw.gw_init_coupling` sets up the iterative
  refinement (`_gw_init_coupling'`) but returns `(0., 0)` before ever calling
  it, so each pair does a fixed amount of work rather than iterating to
  convergence. The allocation and BLAS pressure are real either way.
