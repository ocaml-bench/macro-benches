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

## Knob-A ladder (grammar / automaton scale)

The three grammars form menhir's Knob-A ladder: each rung builds a larger parser automaton
than the one below, so the live set (the state tables, which live across the whole run) and
RSS grow. Knob A here is the *combination* of grammar and generation mode — the three use
different algorithms deliberately, but they are monotone in footprint. Measured on OCaml
5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | program | grammar / mode | wall | gc% | RSS | live heap (top_heap_words) | max pause |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `small` | `menhir_sql_parser` | sql-parser, LALR `-v -t` | 1.2s | 27% | 0.31 GB | 39 M | 15 ms |
| `default` | `menhir_sysver` | sysver, table `-v --table` | 7.8s | 32% | 0.72 GB | 93 M | 12 ms |
| `large` | `menhir_ocamly` | ocaml, canonical `--list-errors --canonical` | 12.7s | 21% | 2.76 GB | 353 M | 21 ms |

RSS and live heap grow monotonically (0.31 → 0.72 → 2.76 GB; 39 → 93 → 353 M words), so each
rung reaches a bigger automaton-construction footprint. gc% is *not* monotone — the canonical
`ocamly` rung is more compute-bound (its `--list-errors` reachability + canonical state
construction dominate), so its gc% (21 %) is lower than the two smaller rungs.

Two caveats worth recording:

- **Time band vs the old numbers.** Earlier docs quoted ~3.3 / 20 / 33 s for these three.
  That was stale: on current hardware the *same* binaries (including the 5.4.1 one) run in
  ~1.2 / 7.8 / 13 s — the workload is unchanged (RSS and collection counts match the old
  figures exactly; only the old walls were anomalous, likely measured under contention or
  thermal throttle). So the menhir ladder is monotone by **footprint** but its wall times are
  compressed into ~1–13 s (tiny → default); it does not reach the 1–3 min "large" time band.
- **A time-large would need `--canonical` on a bigger grammar**, but that knob is a fragile,
  structure-dependent state explosion: `sysver --canonical` is 33 s / 4 GB, yet the *smaller*
  `sql-parser --canonical` blows up to 268 s / 40 GB. So it is left out of the ladder (a
  bigger/huge rung is deferred).

If all three move together, suspect a menhir-internal regression. If only a subset moves, it
points at something specific to that generation algorithm; sysver is the most sensitive to
`Hashtbl` growth cost.

## Notes

Menhir is manually vendored (see `scripts/vendor-menhir.sh`). The output binaries are
standalone copies, not wrapper scripts.
