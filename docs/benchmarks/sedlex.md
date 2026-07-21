# sedlex

sedlex is a Unicode-aware lexer generator for OCaml. Its regex rules are expanded
by a PPX at compile time into a state-table-driven `match`. This benchmark builds a
large chunk of pseudo-code in memory and runs a sedlex tokenizer over it once.

## What it runs

One program, `sedlex_tokenize`, built from `benchmarks/sedlex/sedlex_bench.ml`.

It takes a line count as its only argument (the suite passes `700000`; the source
default when no argument is given is `100000`). The program:

1. Generates the input in memory with a `Buffer`. Each line looks like
   `let var_<i> = func_<i>(<n>, <n>.<n>) + <n>;`, with a `// comment` line every
   10th iteration and a `let s_<i> = "string value <i>";` line every 5th. At 700k
   lines this is roughly 50 MB of text.
2. Wraps it with `Sedlexing.Utf8.from_string` and runs `tokenize`, which walks the
   whole buffer and prepends a token to an accumulator list, then reverses it.
3. Counts identifiers, numbers, and strings and prints the totals.

The tokenizer recognizes identifiers, numbers, string literals, operators,
punctuation, whitespace, and line comments. Identifier, number, and string tokens
each carry a freshly allocated substring via `Sedlexing.Utf8.lexeme`.

## What it stresses

This is a minor-GC workload. Tokenizing produces a flood of short-lived
allocations: one token block per lexeme plus the string each `IDENT`, `NUMBER`, or
`STRING` wraps. The full token list is the only thing held onto, and it does not
live long. Expect high minor-collection pressure and almost no major work.

Two other things it leans on: the PPX-generated DFA, which is a large nested match
that stresses the compiler's match codegen and the emitted lookup tables, and the
UTF-8 decoding path in `Sedlexing.Utf8`.

## Reading the results

At 700k lines, expect wall time around 5.5s with a high gc_overhead near 40%. The
collection counts are lopsided: a few thousand minor collections against only a
handful of major ones (the README observed roughly 2554 minor / 10 major).

A regression here, with no matching movement on the promotion-heavy benchmarks,
points at the minor allocator or the string-allocation path rather than promotion.
It can also point at match-compilation changes, since so much of the work is the
PPX-emitted DFA.

## Notes

Built from the monorepo with `dune build --profile release
benchmarks/sedlex/sedlex_bench.exe`. Uses the vendored `sedlex` under `duniverse/`,
with the `sedlex.ppx` preprocessor. No system libraries or FFI involved.
