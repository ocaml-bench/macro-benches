# coq

Coq (now Rocq) is an interactive proof assistant; `coqc` is its batch compiler.
This benchmark runs `coqc` over one small `.v` file written specifically to make
the Rocq kernel do a lot of reduction work on unary-Peano `nat` (`O | S nat`),
where every `S` constructor the kernel produces is a heap allocation. Rocq sets
its own GC parameters (a 32M-word minor heap and `space_overhead=200`), but only
when `OCAMLRUNPARAM` is unset, so the harness runs it without one.

## Ladder

Input size = the **`make_tree` depth** `D`. Each rung type-checks a tiny vendored
`.v` whose only work is `Compute tree_size (make_tree D)`, which builds a 2^D-node
tree and reduces its size to a 2^D-deep unary `nat`; raising `D` by one more than
doubles the allocation and reduction work, so the ladder is exponential and
discrete. Measured on OCaml 5.4.1, Ryzen 9 9950X, with olly's default ring:

| rung | depth | wall | RSS | gc% | max pause |
| --- | --- | --- | --- | --- | --- |
| `small` | 19 | 8.1s | 2.6 GB | 69% | 222 ms |
| `default` | 20 | 17.9s | 5.7 GB | 74% | 354 ms |
| `large` | 21 | 41.7s | 10.1 GB | 76% | 379 ms |

With Rocq's 256 MB minor heap there are few minor collections (about 200 on
`default`), and each one is long. RSS and pause length grow with depth.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `coqc_corelib_stress` — the original mixed fib/ack/tree kernel-reduction bench
  (anchor; `fib 27`, `sum_to 1900`, `ack 3 11`, `tree_size (make_tree 17)`, about 19s on 5.4.1).

## Notes

- Building `coqc` needs the Rocq prefix in place first (`_rocq_prefix/`, populated
  by `setup-monorepo.sh`) plus the config and dunestrap files under `duniverse/rocq/`.
- The output `coqc-<runtime>` is a wrapper script: it points `ROCQRUNTIMELIB` at the
  runtime's own build, so `rocqworker` and the plugins come from it, and only the
  `.vo` corelib in `_rocq_prefix/` is shared.
