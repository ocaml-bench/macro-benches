# goblint

Goblint is a static analyser for C, based on abstract interpretation with relational
(apron) domains. This benchmark runs it (via the SV-COMP `svcomp.json` config —
interval + octagon/apron) on a bit-vector verification task. It is the suite's
second independent C abstract-interpreter (after frama-c) and the purest
allocation-churn ladder — the reproducer for the OCaml 5 allocation regression
tracked in ocaml#13733.

## Ladder

Input size = the **size of the analysed C program**. `goblint.build.sh` generates a
synthetic Btor2C-style bit-vector state machine — `N` state variables updated in a
`for(;;)` loop via masked bit-vector logic, in the same shape as the frozen `bench.c`
— and analyses it with the same config. A bigger `N` means more variables tracked
and more program points, so the constraint solver does proportionally more fixpoint
work; the values are masked so each rung reaches a fixpoint and proves every assert
safe. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly from
`perf_grp1|re-25|md-2`):

| rung | N | wall | RSS | gc% | allocated | minor GC |
| --- | --- | --- | --- | --- | --- | --- |
| `small` | 100 | 4.3s | 77 MB | 22% | 3.83 G w | 14645 |
| `default` | 165 | 16.3s | 120 MB | 27% | 14.0 G w | 53525 |
| `large` | 240 | 46.6s | 186 MB | 34% | 39.5 G w | 150770 |

The octagon domain is O(N²), so wall and allocation grow super-linearly:
`allocated_words` climbs 3.83 → 39.5 G (10×) and minor collections 15k → 151k while
peak RSS stays modest (77 → 186 MB). **Read this ladder by allocation volume, not
RSS** — it is exactly goblint's #13733 signature (roughly 4× more allocated bytes on
5.x for identical output), and a pure on-heap counterpoint to pplacer's off-heap GSL
footprint. A huge band is deferred (N≈340 would be ~min-scale).

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `goblint` — the FROZEN exact reproducer for ocaml#13733: the fixed ~5.6 KB SV-COMP
  input `btor2c-lazyMod.vcegar_QF_BV_itc99_b13_p02.c`. Too short (~0.2s) for a macro
  rung, but kept because it is the issue repro.

## Notes

- apron is genuinely required (the svcomp config and autotuner both enable it) and is
  non-dune (configure/make + camlidl), so it is the fiddliest build in the suite:
  `scripts/vendor-apron.sh` builds the camlidl/mlgmpidl/apron chain per-runtime into a
  self-contained prefix, exposed to the otherwise-hermetic dune build via `OCAMLPATH`.
- The output `goblint-<runtime>` is a wrapper script (it puts apron's shared libs on
  the loader path and points `pre.custom_includes` at the vendored stub dirs).
- Five vendored-source patches are needed to build on a modern toolchain (goblint.h
  for GCC 14+/C23, a `cpu` `config.h`, a `bare_encoding` install fix, a
  `json-data-encoding` re-alignment, and a first-class-module annotation for 5.5+).
