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
directory too, but the suite runs the 5x version.

The `.ocamlformat` file in this directory is empty, so formatting runs with
ocamlformat's default profile.

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
