# coq

Coq (now Rocq) is an interactive proof assistant. This benchmark runs `coqc`, the batch
compiler, over one small `.v` file that is written specifically to make the Coq kernel do
a lot of reduction work on unary numbers. It is the suite's purest minor-GC allocation
stress test.

## What it runs

One program, `coqc_corelib_stress`. It type-checks `coq_corelib_stress.v`, which uses only
the Rocq `Corelib` (no stdlib) and forces the kernel to reduce four expressions:

- `fib 23` (= 28657), exponential recursion.
- `sum_to 1000`, linear recursion but a large result.
- `ack 3 8` (= 2045), the Ackermann function, super-exponential growth.
- `tree_size (make_tree 13)`, building a balanced binary tree of 16383 nodes and counting it.

Everything runs on Coq's unary-Peano `nat` representation (`O | S nat`), so every `S`
constructor the kernel produces during reduction is a heap allocation. That is the whole
point: the numbers stay small on paper but the kernel allocates enormously to get there.

The build script (`coq.build.sh`) does a `dune build` of Rocq's `coqc_bin.exe` with the
runtime-under-test, then writes out a small wrapper. The output `coqc-<runtime>` is a
wrapper script, not a standalone binary: it sets `OCAMLPATH` and `-coqlib` so the compiler
can find `rocq-runtime` and the Rocq stdlib in `_rocq_prefix/`, then execs the real
`coqc_bin.exe` inside the per-runtime build dir.

## What it stresses

This is the minor allocator, and almost nothing else.

- The minor-GC fast path: a heap-pointer bump for every `S` constructor.
- Constructor block allocation and initialisation on essentially every reduction step.
- Match compilation, since kernel reduction is basically a `match` interpreter over `nat`.

The major GC is barely engaged. The live set stays small even though total throughput is
huge, so major collections are rare.

## Reading the results

Rough baseline numbers on the reference machine:

- Wall around 52s, most of which is GC.
- GC overhead around 94%. That number looks alarming but it is normal here, not a
  pathology: the workload is deliberately allocation-saturated, so the mutator itself
  only accounts for a few seconds and the rest is the minor collector keeping up.
- RSS around 1.1 GB.
- On the order of 6000 minor collections and only about 8 major collections per run.

If this benchmark regresses but the allocation-light benchmarks do not, the problem is
almost certainly in the minor allocator fast path, constructor initialisation, or the
young-pointer write barrier. Conversely, it should be insensitive to major-GC changes:
if a major-GC-only fix moves `coqc`, suspect a side effect.

## Notes

The `.v` file is an intentionally shrunk input. The original used `fib 25`, `ack 3 10`
and friends, which pushed wall time to around 715s and RSS to 4.4 GB. Same character, just
much bigger, so it was cut down to something that runs in under a minute.

Building `coqc` needs the Rocq prefix in place first (`_rocq_prefix/`, populated by
`setup-monorepo.sh`) plus the config and dunestrap files under `duniverse/rocq/`. The
kernel-only workload does not touch Coq's native or VM compute backends, so it does not
exercise the `Marshal` or ephemeron paths those backends use.
