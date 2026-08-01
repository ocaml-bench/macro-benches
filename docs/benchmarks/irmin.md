# irmin

Irmin is a Git-like, persistent, branchable store for OCaml. This benchmark
(`irmin_mem_rw`) drives Irmin's in-memory backend through a read/write workload
built on Lwt promises. It is the only Lwt benchmark in the suite.

## What it runs

One program, `irmin_mem_rw` (built from `irmin_mem_rw.ml`). It builds an
in-memory `Irmin_mem.KV` store over string contents and runs three phases:

1. Write phase: put `n_keys` entries, each a key `key-<i>` with a ~100-byte
   value.
2. Read phase: read back all `n_keys` entries.
3. Mixed phase: run `total_ops` operations against the same key space with a
   fixed read percentage (an op reads when `i mod 100 < read_pct`).

Every write goes through `Store.set_exn` with a fresh commit info, so each
`set` extends Irmin's persistent tree along the path `["root"; key]`. The
program prints per-phase timings and a total.

The workload sizes are command-line arguments, not compile-time constants. The
program takes exactly four positional args: `<n_keys> <n_ops> <read_pct>
<total_ops>`, and exits with a usage message if they are missing. The legacy
`irmin_mem_rw` bench uses 3000 keys, 80% reads, and 20000 mixed ops — a Knob-B
(more-ops) shape. Heads up: the second argument (`n_ops`) is parsed but never
used anywhere in the driver, so only three of the four numbers actually affect
the run.

## Knob-A ladder (store size)

Knob A is the **store size** (`n_keys`), with the mixed-op count kept small so
the write phase — building the store — dominates. Because every `set_exn` puts
its key into the single flat `["root"; …]` directory node, Irmin re-hashes and
re-serializes that whole node on every insert, so the write phase is
**O(n_keys²)** in the persistent-hash-tree / `Hashtbl` churn. That churn is
exactly Irmin's runtime signature, and it — plus the live store and the
major-cycle count — grows with `n_keys`. This is a **churn / throughput** ladder,
not a footprint one: RSS stays modest (< 100 MB). Measured on OCaml 5.5.0,
Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | n_keys | wall | gc% | RSS | live heap (top_heap_words) | minor GC | major GC | max pause |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `_small` | 6000 | 5.4s | 20% | 31 MB | 2.7 M | 9.3k | 293 | 0.49 ms |
| `_default` | 10000 | 15.7s | 25% | 44 MB | 4.4 M | 24k | 674 | 0.79 ms |
| `_large` | 18000 | 51.7s | 29% | 74 MB | 7.9 M | 74k | 1523 | 1.56 ms |

wall (quadratic), gc% (20 → 29 %, rising as churn intensifies), minor/major
collection counts, live store and promotion (6.6 → 11 %) all grow with the store;
pauses stay tiny (< 2 ms). So the ladder is the suite's signal for **Lwt +
persistent-hash-tree allocation churn at scale** — a different regime from the
footprint ladders. A huge band is deferred (the write phase is quadratic; 18k
keys is already ~52 s).

## What it stresses

- Lwt promises. Every store operation returns an `'a Lwt.t` and the whole thing
  runs under `Lwt_main.run`, so this exercises `Lwt.bind` continuation chaining
  at volume. If something regresses here but not on the Eio benchmark, Lwt
  codegen is the first suspect.
- Persistent immutable tree building. Each `set` creates new tree nodes along
  the path rather than mutating in place, so there is steady allocation of
  small tree structure plus the hashing Irmin does over keys and content.
- Moderate GC pressure. The values are small and there is no giant working set,
  so nothing here is extreme.

## Reading the results

Expect a wall time of around 12s, with GC overhead near 11% and a moderate
collection count (roughly 6800 minor / 130 major). Nothing about this benchmark
is a sharp edge; it sits in the middle on every axis, which makes it useful
mostly as the Lwt reference point. Co-movement with `eio_fiber_stream` points
at general scheduler or continuation performance; movement here alone points at
something Lwt-specific.

## Notes

Uses the `irmin` and `irmin.mem` libraries plus `lwt`/`lwt.unix`. Built with
`dune --profile release`; no build quirks.
