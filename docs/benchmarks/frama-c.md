# frama-c

Frama-C is a static-analysis platform for C. The benchmark runs its EVA plugin
(Evolved Value Analysis, an abstract interpreter) over the full SQLite amalgamation
(`sqlite3.c`, ~258k lines) entered through a tiny driver, as a single OCaml process
(`-eva -eva-no-results`). It is the suite's largest weak/ephemeron hash-consing
workload: Frama-C hash-conses its entire CIL AST and EVA hash-conses its abstract
state through `State_builder.Hashconsing_tbl_weak` (OCaml's `Weak.Make`, so
ephemeron-backed). It is the reproducer for ocaml#11733, Frama-C's 3-5x RSS/startup
regression on OCaml 5, rooted in the ephemeron-cleaning path.

## Ladder

Input size = **EVA precision** (`-eva-precision N`, the sqlite wrapper's second
argument; also `FRAMAC_EVA_PRECISION`). Higher precision turns on loop unrolling,
richer domains, and higher plevel/ilevel, growing the AST/state that gets
hash-consed. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`;
olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | prec | wall | RSS | minor GC | gc% | max pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 0 | 7.3s | 457 MB | 11k | 12.9% | 3.1 ms |
| `_default` | 2 | 17.8s | 641 MB | 31k | 10.9% | 8.9 ms |
| `_large` | 3 | 124s | 695 MB | 182k | 2.9% | 11.5 ms |

Each rung reaches a GC regime the one below did not — the exact ocaml#11733 one,
weak/ephemeron hash-consing of the CIL AST + EVA state — with `_large` maximally
exercising the ephemeron key-scan (182k minor collections). Read by minor-GC churn,
not RSS (which saturates ~700 MB). gc% **falls** with size while tail pauses grow:
`_small`/`_default` are GC-throughput-sensitive, `_large` GC-latency-sensitive
(ocaml#14796 territory). `_large` (precision 3) is a deliberate widening-thrash
outlier: its `-eva-auto-loop-unroll 64` lands just below a sqlite loop bound, so EVA
fails to unroll (124s, 48 G allocated); precision 4-9 collapse back to ~8s. No
`huge` (>5 min) rung is reachable via any EVA knob (precision saturates, slevel is
inert); a true one needs a bigger C amalgamation, deferred rather than faked.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`) — the original fixed
EVA analyses; the ladder scales the sqlite one by `-eva-precision`:

- `frama_c_eva_t` — analyses the zlib source `t.c` (~17.5k lines) at
  `-eva-slevel 100`; small and fast (~0.4s), too small for EVA to accumulate state.
- `frama_c_eva_sqlite` — the fixed precision-0 sqlite analysis (== the `_small`
  rung); the ocaml#11733 anchor.

## Notes

Frama-C 32.1 is manually vendored (`scripts/vendor-frama-c.sh`), kernel + EVA only
(WP's `why3` dep caps OCaml < 5.5). It links statically with `-linkall`, runs
`-no-autoload-plugins`, and the wrapper sets `DUNE_DIR_LOCATIONS` at
`vendor/frama-c`. The wrapper also pins two C-preprocessor macros
(`-DLONGDOUBLE_TYPE=double -D'__has_extension(x)=1'`) so different hosts don't
analyse different programs: `__has_extension` gates a 25x wall cliff (gcc ≥ 14 only)
and `LONGDOUBLE_TYPE` otherwise aborts EVA on a long-double branch. Changing them
moves the alarm count and wall time.
