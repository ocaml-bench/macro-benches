# ocamlformat

OCamlformat is an auto-formatter for OCaml source. It parses a file to an AST and
pretty-prints it back out according to its formatting rules. This benchmark
(`ocamlformat_rocq`) runs it on one large source file and times the format.

## What it runs

One process: the built `ocamlformat` (from `duniverse/ocamlformat/`, compiled by
`ocamlformat.build.sh`) formatting `workload_5x.ml`. The command is:

```
ocamlformat --impl workload_5x.ml -o /dev/null
```

`workload_5x.ml` is about 663 KB, roughly 16600 lines of OCaml extracted from the Rocq
prover source. Output goes to `/dev/null`, so the benchmark is purely the parse +
format work, not disk I/O. There is a smaller `workload.ml` (about 3300 lines) in the
directory too, but the legacy `ocamlformat_rocq` bench runs the 5x version.

The `.ocamlformat` file in this directory is empty, so formatting runs with
ocamlformat's default profile. Note that ocamlformat only formats a file if it finds a
project root (a `.ocamlformat`, or `dune-project`, etc.) at or above the input file's
directory — otherwise it prints "Ocamlformat disabled ... no project root was found" and
copies the input through unchanged. The rung inputs therefore must live in this directory,
beside `.ocamlformat`.

## Knob-A ladder (source size)

Knob A is the **size of the formatted source** (number of lines). The rung inputs
`wl_{12,30,150}x.ml` are **generated** by `ocamlformat.build.sh` (N-times concatenation of
the real `workload.ml` — ocamlformat only parses and reprints syntax, so the duplicated
top-level definitions are perfectly valid input) and gitignored, since they are large.
Only the ~130 KB `workload.ml` is vendored.

Unlike the compiler benchmarks (`ocamlc_self_compile`), where compilation is ~linear and
*shape-invariant* (each module is compiled and discarded, so the live set stays bounded no
matter how big the program), ocamlformat parses the **whole file into one AST and holds it
plus the output document in memory at once**. So the live heap and RSS grow with the input
— this is a genuine Knob A. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh`,
`v=0x400`):

| rung | input | lines | wall | RSS | live heap (top_heap_words) | promo frac |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | `wl_12x.ml` | ~40k | 4.7s | 0.6 GB | 74.9 M | 0.099 |
| `_default` | `wl_30x.ml` | ~100k | 12.7s | 1.7 GB | 213 M | 0.099 |
| `_large` | `wl_150x.ml` | ~500k | 90s | 8.8 GB | 1.12 G | 0.101 |

RSS grows ~linearly and wall slightly super-linearly (~n^1.2); the promotion fraction holds
steady at ~10%, so the shape is consistent — each rung is the same AST-heavy /
`Format`-heavy workload at a larger live set, reaching a footprint the rung below did not. A
huge band (~450x, ~26 GB RSS) is reachable but deferred (tracked separately).

olly gc-profile (running-ng `perf_grp1|re-25|md-2`, 5.5.0, one invocation; harness clean —
minor-collection counts match `v=0x400` exactly):

| rung | wall | gc% | gc_time | max_rss_kb_excl_ring | max pause | p99.9 pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 4.8s | 32.6% | 1.56s | 0.58 GB | 5.2 ms | 2.3 ms |
| `_default` | 13.2s | 31.9% | 4.21s | 1.61 GB | 12.7 ms | 6.1 ms |
| `_large` | 100s | 28.6% | 28.6s | 8.41 GB | 90.3 ms | 25.4 ms |

ocamlformat has a distinct profile from the other laddered tools. Where zarith / frama-c /
owl all see gc% *fall* as inputs grow (the mutator or FFI takes over), ocamlformat holds a
**constant ~30% gc%** at every size — it is uniformly minor-GC-heavy (light ~1.2% promotion,
transient `Format` boxes). At the same time the **max pause climbs to ~90 ms at `_large`**
(p99.9 ~25 ms) — the largest single GC pause anywhere in the suite — because the major heap
holds a multi-GB live AST and each major slice has to scan it. So the ladder is a strong dual
signal: steady minor-GC throughput sensitivity across all rungs, plus growing major-GC
scan-latency at the top.

## What it stresses

This is a minor-GC-heavy, AST-shaped workload with light promotion. Most of the
allocation is short-lived, so it leans on the minor collector rather than the major
heap.

- `Format`: the pretty-printing pipeline is built on `Format` boxes (`pp_*`, `box`,
  `hov`, `cut`) plus a lot of `String.concat` / `Buffer.add_*`. This is the bulk of
  the workload.
- OCaml AST construction (`Parsetree.structure`) during parsing.
- OCamlformat's AST-transform passes: several traversals over the tree (normalising,
  attribute handling, and so on).

## Reading the results

On 5.4.1 baseline, expect wall time around 5s, GC overhead around 30%, and on the
order of 2900 minor / 22 major collections. Promotion is light; most allocation is
transient `Format` boxes.

It tends to move together with the other AST-shaped benchmarks (`liq_parse_typecheck`)
and with heavy `Buffer`/`Format` users (`sedlex_tokenize`). If it moves on its own,
suspect something specific to ocamlformat's transform pipeline.

## Notes

The program is named `ocamlformat_rocq` after the source of its input file. The output
binaries are standalone copies, not wrapper scripts.
