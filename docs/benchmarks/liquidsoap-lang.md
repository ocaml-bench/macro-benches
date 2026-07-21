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
default is only 200 iterations (the `iterations` ref in `liq_bench.ml`). The suite drives
it with a much larger count (on the order of 50000) to get a meaningful wall time, so the
headline numbers below assume the large count, not the built-in default.

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
