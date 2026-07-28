# sedlex

sedlex is a Unicode-aware lexer generator for OCaml. Its regex rules are expanded
by a PPX at compile time into a state-table-driven `match`. This benchmark builds a
large chunk of pseudo-code in memory and runs a sedlex tokenizer over it once.

## What it runs

One program, `sedlex_tokenize`, built from `benchmarks/sedlex/sedlex_bench.ml`.

It takes a line count as its only argument. The legacy `sedlex_tokenize` bench passes
`700000` (~1.6s on 5.5.0); the source default when no argument is given is `100000`. The
program:

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

## Knob-A ladder (input size)

Knob A is the input size (`argv.1` = generated line count), read straight from the
argument — no generated files, so wiring is just a different arg per rung. Although each
token is short-lived in principle, the driver **retains the whole token list** (and the
substrings the `IDENT`/`NUMBER`/`STRING` tokens carry) until the end, plus the generated
input string, so the live set — and RSS — grow ~linearly with the input. This makes size a
genuine footprint Knob A. Tokenising is cheap, so wall grows only ~linearly and reaching the
larger time bands needs big inputs and a lot of RAM. Measured on OCaml 5.5.0, Ryzen 9 9950X
(`fingerprint.sh`, `v=0x400`):

| rung | lines | wall | RSS | live heap (top_heap_words) | promo frac |
| --- | --- | --- | --- | --- | --- |
| `_small` | 2M | 4.6s | 2.8 GB | 379 M | 0.175 |
| `_default` | 6M | 13.7s | 8.5 GB | 1.14 G | 0.174 |
| `_large` | 20M | 46s | 28 GB | 3.83 G | 0.171 |

RSS grows ~linearly (2.8 → 28 GB) and the promotion fraction holds steady at ~0.17, so each
rung is the same tokenise-and-retain workload at a bigger live set. `_large` lands at 46s,
just under the 1-3 min band — capped there by RAM (28 GB); pushing into the band would need
~37 GB, so it is left at 20M. A huge band is deferred (tracked separately).

Note (correcting an earlier reading): the major-collection count stays pinned at ~9 across
every size — because the token list is almost all live until the run ends, there is little
for the major collector to reclaim mid-run, so growth shows up as live-heap/RSS, not as more
major cycles.

olly gc-profile (running-ng `perf_grp1|re-25|md-2`, 5.5.0, one invocation; harness clean.
olly wall exceeds the `v=0x400` wall because of attach + ring overhead on the multi-GB runs):

| rung | wall | gc% | gc_time | max_rss_kb_excl_ring | max pause | p99.9 pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 4.8s | 42.7% | 2.05s | 2.68 GB | 20.8 ms | 10.5 ms |
| `_default` | 16.6s | 48.7% | 8.08s | 8.08 GB | 56.6 ms | 31.0 ms |
| `_large` | 74.1s | 60.9% | 45.1s | 27.05 GB | 153 ms | 85.2 ms |

sedlex has the most extreme GC profile in the suite, and a distinctive one: **gc% rises with
size** (43% → 61%), the opposite of zarith / frama-c / owl (which fall) and unlike ocamlformat
(flat). The reason is the retained token list — as it grows into a multi-GB live heap, every
minor collection has more surviving young objects to promote and more live heap to scan, so
GC's share of wall climbs. The **max pause reaches ~153 ms at `_large`** (p99.9 ~85 ms) — the
largest anywhere in the suite. So sedlex is the primary signal for minor-GC / promotion
throughput and pause behaviour under a large, mostly-live heap.

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
