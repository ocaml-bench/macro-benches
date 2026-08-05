# liquidsoap-lang

Liquidsoap is an audio/video stream-scripting language; `liquidsoap-lang` is its
front-end library (parser, typechecker, evaluator) split out from the full application.
This benchmark builds a fresh AST with `Runtime.parse` and runs type inference over it
with `Runtime.type_term`, nothing cached between rounds — so it is one of the most
promotion-heavy workloads in the suite, leaning on the minor-to-major copy path plus
`Hashtbl`/`ref` traffic and `Lazy.force` in unification.

## Ladder

Input size = the **size of the script** — a bigger AST and type environment, not more
repetitions of a small one. A second argument (`argv.2`) is a unit count: the driver
generates a script of that many independent recursion + higher-order + list blocks (same
liquidsoap idioms as the fixed script) and parses + typechecks it **once**, in process, so
no vendored files are needed. Measured on 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`;
gc% from olly `perf_grp1|re-25|md-2`):

| rung | units | script | wall | RSS | gc% | live heap | promo frac |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `_small` | 4000 | ~1.1 MB | 4.8s | 0.26 GB | 59% | 37 M | 0.22 |
| `_default` | 6500 | ~1.8 MB | 14.3s | 0.44 GB | 60% | 61 M | 0.24 |
| `_large` | 12000 | ~3.3 MB | 63.5s | 0.72 GB | 59% | 113 M | 0.25 |

RSS, live heap and the major-collection count (94 → 131 → 210) all grow with the script,
so each rung reaches a bigger AST + type-environment regime. **wall is super-quadratic** in
the unit count (~n^2.1) — the type environment grows and each unit unifies against it, so
the run gets GC-and-inference-bound fast. gc% holds a **constant ~60%** across all rungs:
the parse-and-promote path dominates at every size, making this one of the most
promotion-heavy, GC-throughput-sensitive workloads in the suite. A huge band is deferred.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `liq_parse_typecheck` — the original fixed-script repetition bench (~50000x an
  embedded ~80-line script).

## Notes

- Build uses Jane Street ppxlib, which needs a recent OCaml (5.3+) at build time; it is
  build-time only and does not affect the runtime measurement.
- The Liquidsoap `Marshal`-based type-cache path is disabled here, so this benchmark does
  not exercise `Marshal`.
- The output is a plain copied standalone binary, not a wrapper script.
