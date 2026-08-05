# coq

Coq (now Rocq) is an interactive proof assistant; `coqc` is its batch compiler.
This benchmark runs `coqc` over one small `.v` file written specifically to make
the Rocq kernel do a lot of reduction work on unary-Peano `nat` (`O | S nat`),
where every `S` constructor the kernel produces is a heap allocation. It is the
suite's purest minor-GC allocation stress test — almost nothing but the minor
allocator fast path.

## Ladder

Input size = the **`make_tree` depth** `D`. Each rung type-checks a tiny vendored
`.v` whose only work is `Compute tree_size (make_tree D)`, which builds a 2^D-node
tree and reduces its size to a 2^D-deep unary `nat`; raising `D` by one more than
doubles the allocation and reduction work, so the ladder is exponential and
discrete. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly
gc%/pause from `perf_grp1|re-25|md-2`):

| rung | depth | wall | RSS | gc% | max pause |
| --- | --- | --- | --- | --- | --- |
| `small` | 17 | 5.3s | 0.57 GB | 90.0% | 18.9 ms |
| `default` | 18 | 18.8s | 0.98 GB | 94.1% | 32.8 ms |
| `large` | 19 | 68.6s | 1.89 GB | 96.8% | 63.6 ms |

This is the **most GC-bound benchmark in the suite** — 90–97% gc%, rising with
depth, because the workload is almost pure minor-heap allocation of unary-nat
constructors. RSS and pause length grow monotonically with depth. A huge band
(D≥20) is deferred: the ladder is exponential (D=21 already exceeds 200s).

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `coqc_corelib_stress` — the original mixed fib/ack/tree kernel-reduction bench
  (anchor; `fib 23`, `sum_to 1000`, `ack 3 8`, `tree_size (make_tree 13)`).

## Notes

- Building `coqc` needs the Rocq prefix in place first (`_rocq_prefix/`, populated
  by `setup-monorepo.sh`) plus the config and dunestrap files under `duniverse/rocq/`.
- The output `coqc-<runtime>` is a wrapper script, not a standalone binary: it sets
  `OCAMLPATH`/`-coqlib` and execs the real `coqc_bin.exe` inside the build dir.
