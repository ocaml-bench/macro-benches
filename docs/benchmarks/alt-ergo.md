# alt-ergo

Alt-Ergo is an SMT solver aimed at program-verification problems. The benchmark
builds one standalone `alt-ergo` binary (`Main_text.exe`, copied out — not a
wrapper) and drives it on a generated verification goal. The solving work is
compute-bound in the theory backend (DPLL(T), congruence closure, arithmetic),
but on the runtime side it leans hard on `Weak.Make` term hash-consing
(`hconsing.ml`), which is ephemeron-backed — one of the suite's two hot
weak-array workloads (Frama-C's CIL hash-consing is the other).

## Ladder

Input size = the **single-solve problem size** `N` (`alt-ergo.build.sh` generates
`alt_ergo_chain_<rung>.why`: assert `a(0)=0` and `a(i)=a(i-1)+1` for `i` in
`1..N`, prove `a(N)=N`). Solving is super-linear (~N^2.2 in both wall and live
heap), so each rung builds a strictly bigger congruence/arithmetic structure than
the one below. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`;
olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | N | wall | RSS | gc% | top_heap | max pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 4000 | 4.2s | 0.59 GB | 13.6% | 76M w | 3.9 ms |
| `_default` | 7000 | 14.1s | 1.88 GB | 17.8% | 244M w | 11.0 ms |
| `_large` | 10500 | 37.8s | 4.88 GB | 25.7% | 638M w | 27.4 ms |

Unlike most ladders here, **gc% rises** with N (13.6 → 25.7%) and **pauses grow
steeply** (max 4 → 27 ms): the solve builds one large, mostly-live structure
(promotion ~0.1, major cycles only 16 → 24), so the cost is scanning an
ever-bigger live heap on each major slice — a heap-scan-bound ladder. A huge band
is deferred (N≈14000 ≈ min-scale at ~9 GB).

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `alt_ergo_fill` — 100 independent copies of one goal (`fill_x100.why`,
  generated), scaled by repetition; ~14s at ~0.14s per goal.
- `alt_ergo_yyll` — a larger single native `.why` input through the native parser.
- `alt_ergo_unsat_smt2` — a Dolmen `.smt2` input run with `--timelimit 15`; the
  goal never closes and it dies of its own SIGVTALRM, exiting 142 by design.

## Notes

All alt-ergo programs SIGSEGV under ocaml-mmtk (moving collector relocates a value
a zarith→GMP C stub holds a raw pointer to), so they are excluded from the MMTk
sweeps. They run fine on the stock and PR-branch runtimes.
