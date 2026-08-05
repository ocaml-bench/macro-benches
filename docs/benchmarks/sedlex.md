# sedlex

sedlex is a Unicode-aware lexer generator for OCaml; its regex rules are expanded
by a PPX at compile time into a state-table-driven `match`. The benchmark generates
a large chunk of pseudo-code in memory (`let`/`func`/`string`/comment lines), runs a
UTF-8 sedlex tokenizer over it, and **retains the whole token list** until the end —
so it stresses the minor allocator, the string-allocation path, and the PPX-emitted DFA.

## Ladder

Input size = the **generated line count** (`argv.1`), read straight from the argument —
no generated files. The retained token list (plus the substrings each `IDENT`/`NUMBER`/
`STRING` carries) makes the live set, and RSS, grow ~linearly with the input; the
promotion fraction holds ~0.17, so each rung is the same tokenise-and-retain workload at
a bigger live set. Measured on 5.5.0, Ryzen 9 9950X (wall/RSS from `fingerprint.sh`
`v=0x400`; gc%/pause from olly `perf_grp1|re-25|md-2`):

| rung | lines | wall | RSS | gc% | max pause | p99.9 pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 2M | 4.6s | 2.8 GB | 42.7% | 20.8 ms | 10.5 ms |
| `_default` | 6M | 13.7s | 8.5 GB | 48.7% | 56.6 ms | 31.0 ms |
| `_large` | 20M | 46s | 28 GB | 60.9% | 153 ms | 85.2 ms |

sedlex has the most extreme GC profile in the suite, and a distinctive one: **gc% rises
with size** (43% → 61%), the opposite of zarith/owl (which fall), because every minor
collection has more surviving young objects to promote as the token list grows. The
**max pause reaches ~153 ms at `_large`** — the largest anywhere in the suite. Major
cycles stay pinned at ~9 across all rungs (the list is mostly live to the end), so growth
shows up as live-heap/RSS, not more major work. `_large` is RAM-capped at 20M (28 GB);
a huge band is deferred.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `sedlex_tokenize` — the original fixed-input bench (700k lines, ~1.6s); one regime,
  more samples.

## Notes

- Uses the vendored `sedlex` under `duniverse/` with the `sedlex.ppx` preprocessor.
  No system libraries or FFI involved.
