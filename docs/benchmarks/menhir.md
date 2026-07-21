# menhir

Menhir is an LR(1) parser generator for OCaml. It reads a grammar (`.mly`) and
produces a parser plus its state tables. This directory holds three benchmarks that
run the same menhir binary on three different grammars, at three different scales and
with three different generation modes. All three are built by `menhir.build.sh`, which
just does a `dune build` of `duniverse/menhir/src/stage2/main.exe` with the
runtime-under-test's compiler and copies the binary out.

## What it runs

Three separate programs, each running the built menhir on one grammar. The grammar
files live in this directory. The run flags come from the running-ng suite config, not
from the build script.

| program | grammar | size | mode | flags |
| --- | --- | --- | --- | --- |
| `menhir_ocamly` | `ocaml.mly` | ~3000 lines | canonical LR(1) | `--list-errors --no-stdlib --canonical` |
| `menhir_sql_parser` | `sql-parser.mly` (+ `keywords.mly`) | ~5800 lines | LALR, verbose | `-v -t ... --base sql-parser` |
| `menhir_sysver` | `sysver.mly` | ~12700 lines | table-driven | `-v --table` |

A few things worth knowing about each:

- `menhir_ocamly` builds the *canonical* LR(1) automaton for the OCaml grammar.
  Canonical LR(1) keeps every distinct `(state, lookahead)` pair instead of merging
  them the way LALR does, so the state table is huge. On top of that, `--list-errors`
  makes menhir enumerate all the error states, which is itself a heavy reachability
  computation. This is the biggest of the three by far.
- `menhir_sql_parser` generates a parser from the SQL grammar with LALR plus verbose
  output (`-v` writes the `.automaton` and `.conflicts` dumps, `-t` the table). Smaller
  scale.
- `menhir_sysver` runs the largest grammar in table-driven mode with `-v`. You can see
  its byproducts checked into the directory: `sysver.ml` (the generated parser, tens of
  MB), `sysver.automaton`, and `sysver.conflicts`.

## What it stresses

All three are minor-GC-heavy and share the same shape of work:

- `Hashtbl` at scale, keyed on parser states. This grows with the automaton, so the
  larger grammars push it hardest (sysver most of all).
- Large-array allocation for the state tables.
- Polymorphic `compare`, used by `Set.Make` and `Hashtbl` on structured keys.
- `Format` for the codegen and the verbose table/automaton dumps.
- AST/IR allocation for the grammar itself.

## Reading the results

Rough baseline numbers:

- `menhir_ocamly`: wall around 33s, GC overhead around 20%, RSS around 2.7 GB. The
  RSS really is that large; the canonical state table lives across the whole run.
- `menhir_sql_parser`: wall around 3.3s, GC overhead around 29%. The small one.
- `menhir_sysver`: wall around 20s, GC overhead around 33%, on the order of 8850 minor
  / 50 major collections.

The three form a natural triple. If all three move together, suspect a menhir-internal
regression. If only a subset moves, it points at something specific to that generation
algorithm. Because they differ mostly in scale of `Hashtbl` and array growth, sysver
is the most sensitive to `Hashtbl` growth cost.

## Notes

Menhir is manually vendored (see `scripts/vendor-menhir.sh`). The output binaries are
standalone copies, not wrapper scripts.
