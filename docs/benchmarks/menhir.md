# menhir

Menhir is an LR(1) parser generator: it reads a grammar (`.mly`) and produces a
parser plus its state tables. The benchmark runs the vendored menhir on real
grammars; the work is minor-GC-heavy — `Hashtbl` keyed on parser states (grows
with the automaton), large-array allocation for the state tables, polymorphic
`compare`, and `Format` for codegen/dumps.

## Ladder

Menhir has no callable main to loop in-process, so the input-size axis is the
**size of the parser automaton** — grown by feeding a bigger grammar and/or the
fuller `--canonical` LR(1) construction. The rungs are therefore three distinct
grammar/mode configs (not a single scaled parameter); each rung's state tables
live across the whole run, so RSS and live heap grow with it. Measured on 5.5.0,
Ryzen 9 9950X:

| rung | program / config | wall | gc% | RSS | live heap | max pause |
| --- | --- | --- | --- | --- | --- | --- |
| small | `menhir_sysver` — sysver, `--table` | 7.8s | 32% | 0.72 GB | 93 M w | 11.7 ms |
| default | `menhir_ocamly` — ocaml, `--canonical --list-errors` | 13.2s | 20% | 2.76 GB | 353 M w | 20.6 ms |
| large | `menhir_sysver_canonical` — sysver, `--canonical` | 34.4s | 36% | 4.0 GB | 513 M w | 21.4 ms |

Wall, RSS, live heap, minor-collection count and pause length all grow monotonically
(0.72 → 4.0 GB; 93 → 513 M words). gc% is not monotone — the `ocamly` default is more
compute-bound (canonical construction + `--list-errors` reachability dominate its wall),
so its 20% dips below the two `sysver` rungs.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `menhir_sql_parser` — a fast standalone LALR-path bench (sql-parser, `-v -t`, ~1.2s /
  0.31 GB). Not a ladder rung: LALR caps it at ~1.2s and `--canonical` blows up to
  268s / 40 GB (a fragile state explosion), so there is no usable middle.

## Notes

Manually vendored (`scripts/vendor-menhir.sh`); the output binaries are standalone copies,
not wrappers.
