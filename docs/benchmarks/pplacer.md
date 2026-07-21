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
