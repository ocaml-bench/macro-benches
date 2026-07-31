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
| `menhir_sysver_canonical` | `sysver.mly` | ~12700 lines | canonical LR(1) | `--canonical` |

(`menhir_sysver` and `menhir_sysver_canonical` run the same grammar under two constructions —
table-driven vs canonical LR(1) — which is the small vs large end of the Knob-A ladder below.)

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

## Knob-A ladder (automaton scale)

Knob A is the **size of the parser automaton** menhir builds — grown by feeding a bigger
grammar and/or using the fuller `--canonical` LR(1) construction. Each rung's state tables
live across the whole run, so RSS and the live set grow with it. Menhir has **no callable
main to loop in-process** (its `main.ml` is 16 lines — the whole pipeline runs as init-time
side effects of linking), so a bigger single input is the only way to lengthen a run; a shell
loop does not help because running-ng re-attaches olly/perf to the first child only. Measured
on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly gc%/pause from
`perf_grp1|re-25|md-2`):

| rung | program | grammar / mode | wall | gc% | RSS | live heap (top_heap_words) | max pause |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `small` | `menhir_sysver` | sysver, table `-v --table` | 7.8s | 32% | 0.72 GB | 93 M | 11.7 ms |
| `default` | `menhir_ocamly` | ocaml, canonical `--list-errors --canonical` | 13.2s | 20% | 2.76 GB | 353 M | 20.6 ms |
| `large` | `menhir_sysver_canonical` | sysver, canonical `--canonical` | 34.4s | 36% | 4.0 GB | 513 M | 21.4 ms |

wall, RSS, live heap, minor-collection count and pause length all grow monotonically
(7.8 → 13.2 → 34.4 s; 0.72 → 2.76 → 4.0 GB; 93 → 353 → 513 M words). gc% is *not* monotone —
the `ocamly` default is more compute-bound (canonical construction + `--list-errors`
reachability dominate its wall), so its gc% (20 %) dips below the two `sysver` rungs (32/36 %).

Two notes:

- **The old ~3.3 / 20 / 33 s figures were stale.** On current hardware the single-grammar
  runs are much faster than they used to appear (the same 5.4.1 binary runs in seconds, not
  tens of seconds — the workloads are unchanged, only the old walls were anomalous, likely
  measured under contention or thermal throttle). The ladder above restores measurable,
  monotone times by picking heavier configs, not by any workload change.
- **`menhir_sql_parser`** (sql-parser, LALR, ~1.2 s / 0.31 GB) stays in the suite as a fast
  standalone LALR-path bench — it is *not* a ladder rung (LALR caps it at ~1.2 s and
  `sql-parser --canonical` blows up to 268 s / 40 GB, a fragile structure-dependent state
  explosion, so there is no usable middle for it).

If all three move together, suspect a menhir-internal regression. If only a subset moves, it
points at something specific to that generation algorithm; sysver is the most sensitive to
`Hashtbl` growth cost.

## Notes

Menhir is manually vendored (see `scripts/vendor-menhir.sh`). The output binaries are
standalone copies, not wrapper scripts.
