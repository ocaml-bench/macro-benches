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

The wrapper takes two arguments, one per knob:

- `$1` — **Knob B (repetition)**: the number of full passes over the grid
  (`Sys.argv.(1)`, default 1). The live set and heap shape stay constant; more
  passes just give more samples of the same regime.
- `$2` — **Knob A (working set)**: the matrix dimension, exported as
  `OWL_MATRIX_DIM` (default 100). Each sample point becomes a `$2 x $2` matrix,
  so the off-heap Bigarray live set is `100 * $2^2 * 8` bytes and grows RSS
  ~quadratically.

The whole run is a single OCaml process that olly can observe end to end. The
legacy `owl_gc` bench runs at `arg=6` (loop 6, dim 100) on the `re-25` ring; the
`owl_gc_{small,default,large,huge}` rungs run at loop 1 with growing dim.

Decoupling note: the driver originally hardcoded `dim = num_sample_pts = 100`
and built the probability vector `u` with length `num_sample_pts`. That only
type-checked at runtime because the two were equal — `u` is multiplied against
the `dim x dim` distance matrices, so its length must be `dim`. `u` was changed
to `Gw.uniform_dist dim` (the mathematically correct length: one weight per
point of the space), which decouples `dim` from `num_sample_pts` and makes `dim`
an independent Knob A.

## Knob-A ladder (matrix dimension)

Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh`, `v=0x400`, loop 1,
`num_sample_pts` fixed at 100):

| rung | dim | wall | RSS | allocated_words |
| --- | --- | --- | --- | --- |
| `_small` | 300 | 4.0s | 95 MB | 27 M |
| `_default` | 500 | 11s | 230 MB | 59 M |
| `_large` | 1500 | 124s | 1.9 GB | 459 M |
| `_huge` | 2400 | 453s | 4.77 GB | 1.16 G |

The acceptance signal is **RSS**: it grows ~quadratically in `dim` (95 MB →
4.77 GB) as the off-heap Bigarray live set grows, so each rung reaches a
footprint regime the one below did not. Two owl-specific caveats:

- `top_heap_words` is **flat at 62804 across every rung** — the Bigarray bulk
  data lives off-heap and is not counted in the on-heap peak. This is the
  off-heap-heavy case the refactor plan flags: lean on RSS and `allocated_words`,
  not `top_heap_words`, for the shape verdict here.
- Wall time is **BLAS-thread-bound** (OpenBLAS uses all cores; `user_s` runs
  ~30x wall), so the time bands are less stable across machines than RSS. RSS is
  deterministic and is the primary way to read this ladder; wall is secondary.

olly gc-profile (running-ng `perf_grp1|re-25|md-2`, 5.5.0, one invocation; harness
clean). Wall here runs above the `v=0x400` numbers above because olly's attach +
ring add overhead to the heavily-threaded run:

| rung | wall | gc% | gc_time | max_rss_kb_excl_ring | max pause | p99.9 pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 4.5s | 24.1% | 1.08s | 94 MB | 1.6 ms | 0.06 ms |
| `_default` | 13.8s | 10.5% | 1.44s | 225 MB | 3.4 ms | 0.25 ms |
| `_large` | 139s | 8.3% | 11.6s | 1.85 GB | 27.4 ms | 13.3 ms |
| `_huge` | 576s | 8.2% | 47.1s | 4.6 GB | 53.1 ms | 25.2 ms |

Complementary coverage: `_small` is GC-**throughput**-heavy (24% gc%) while `_large`
and `_huge` are GC-**latency** benches — the max pause grows to 27 ms then 53 ms
(p99.9 to 25 ms) as the collector scans and finalises multi-GB of off-heap custom
blocks. These are the steepest pauses in the suite, so the owl ladder is the primary
signal for major-GC scan/finalise latency at a large off-heap footprint (as well as
the `custom_major_ratio` pacer at `_large`/`_huge`, whose 18–46 MB Bigarrays are big
enough to move pacer policy — `owl_gc` at dim 100 is not). Minor:major collection
counts stay near 2:1 across all rungs (the Bigarray-finalisation fingerprint).

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
