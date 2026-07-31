# liquidsoap-lang

Liquidsoap is an audio/video stream-scripting language; `liquidsoap-lang` is its
front-end library (parser, typechecker, evaluator) split out from the full application.
This benchmark takes one fixed Liquidsoap script and parses plus typechecks it over and
over, so it measures the cost of building an AST and running type inference across it.

## What it runs

One program, `liq_parse_typecheck` (built from `liq_bench.ml`). It embeds a roughly
80-line Liquidsoap script that exercises a spread of language features: recursive
functions (`fib`, `factorial`), list combinators written in the language itself (`map`,
`filter`, `fold`, `range`), pattern matching via `list.case`, string interpolation and
concatenation, function composition, and a chain of `let` bindings to give the type
environment some work.

Each iteration calls `Liquidsoap_lang.Runtime.parse` to build a fresh AST from the
script text, then `Liquidsoap_lang.Runtime.type_term` to typecheck it. Nothing is cached
between iterations, so every round allocates a whole new AST, typechecks it while it is
still live, and then lets it fall out of scope.

The iteration count comes from `Sys.argv.(1)`. Worth noting: the binary's built-in
default is only 200 iterations (the `iterations` ref in `liq_bench.ml`). The legacy
`liq_parse_typecheck` bench drives it with a much larger count (~50000) to get a
meaningful wall time — that is the Knob-B (repetition) form.

## Knob-A ladder (script size)

Knob A is the **size of the script** — a bigger AST and a bigger type environment, rather
than more repetitions of a small one. A second argument (`argv.2`) is a *unit count*: when
given, the driver generates a script of that many independent units (each a self-contained
recursion + higher-order + list block, using the same liquidsoap idioms as the fixed
script, with a unique suffix) and parses + typechecks it **once**. Generating in-process
avoids any vendored/generated files. Measured on OCaml 5.5.0, Ryzen 9 9950X
(`fingerprint.sh` `v=0x400`; olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | units | script | wall | gc% | RSS | live heap (top_heap_words) | promo frac |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `_small` | 4000 | ~1.1 MB | 4.8s | 59% | 0.26 GB | 37 M | 0.22 |
| `_default` | 6500 | ~1.8 MB | 14.3s | 60% | 0.44 GB | 61 M | 0.24 |
| `_large` | 12000 | ~3.3 MB | 63.5s | 59% | 0.72 GB | 113 M | 0.25 |

RSS, live heap and the major-collection count (94 → 131 → 210) all grow with the script, so
each rung reaches a bigger AST + type-environment regime. **wall is super-quadratic** in the
unit count (~n^2.1) — the type environment grows and each unit's inference unifies against
it, so the run gets GC-and-inference-bound fast (D=30000 already exceeds 200 s). gc% holds a
**constant ~60 %** across all rungs — the parse-and-promote path dominates at every size, one
of the most promotion-heavy, GC-throughput-sensitive workloads in the suite. A huge band is
deferred.

## What it stresses

This is a promotion-heavy workload, one of the most promotion-heavy in the suite.

- The AST is a set of recursive variants, so parsing does a lot of small-block
  allocation.
- Each AST is built, typechecked while still alive, then dropped, which means a large
  fraction of what is allocated survives a minor collection and gets copied into the
  major heap. That minor-to-major copy path is exactly what this benchmark leans on.
- Type inference uses unification, so there is `ref`-cell mutation in type variables and
  `Hashtbl` traffic for the inference environment. `Lazy.force` shows up on the hot path
  too, and type printing goes through `Format`.
- The Jane Street PPX dependency is build-time only. It does not affect the runtime
  measurement.

## Reading the results

Rough baseline: wall around 26s at the large iteration count, gc_overhead around 22%,
with roughly a 48% major-to-minor collection ratio (about 26k minor against 12.7k major).
That major:minor ratio is unusually high and is the point of the benchmark.

AST-with-type-inference is a very common OCaml workload shape (compilers, DSLs, language
servers), so this is a good general probe. A regression here most likely points at the
minor-to-major copy path or at `Hashtbl` performance. If a similar AST-shaped benchmark
moves at the same time, suspect a general AST/promotion issue; if only this one moves,
suspect something liquidsoap-specific.

## Notes

- The build uses Jane Street ppxlib, which needs a recent OCaml (5.3 or newer) at build
  time.
- There is a Liquidsoap type-cache path (`Marshal`-based) that is disabled here, so this
  benchmark does not exercise `Marshal` despite living in a compiler-shaped domain.
- The output is a plain copied standalone binary (not a wrapper script).
