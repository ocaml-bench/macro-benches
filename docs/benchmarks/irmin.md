# irmin

Irmin is a Git-like, persistent, branchable store for OCaml. This benchmark
builds an in-memory `Irmin_mem.KV` store over string contents and runs a
write/read/mixed workload on top of Lwt promises — the only Lwt benchmark in the
suite, so it exercises `Lwt.bind` continuation chaining at volume alongside
persistent-tree allocation.

## Ladder

The ladder scales the **store size** (`n_keys`), with the mixed-op count kept
small so the write phase dominates. Because every `set_exn` puts its key into the
single flat `["root"; …]` directory node, Irmin re-hashes and re-serializes that
whole node on every insert, so the write phase is **O(n_keys²)** in
persistent-hash-tree / `Hashtbl` churn. Measured on OCaml 5.5.0, Ryzen 9 9950X
(`fingerprint.sh` `v=0x400`; olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | n_keys | wall | RSS | gc% | major GC | max pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 6000 | 5.4s | 31 MB | 20% | 293 | 0.49 ms |
| `_default` | 10000 | 15.7s | 44 MB | 25% | 674 | 0.79 ms |
| `_large` | 18000 | 51.7s | 74 MB | 29% | 1523 | 1.56 ms |

This is a **churn / throughput** ladder, not a footprint one: RSS stays modest
(< 100 MB) and pauses stay tiny (< 2 ms), while wall grows quadratically and gc%
rises (20 → 29 %) as churn intensifies. It is the suite's signal for Lwt plus
persistent-hash-tree allocation churn at scale; co-movement with the Eio
benchmark points at general scheduler/continuation performance, movement here
alone at something Lwt-specific. A huge band is deferred (the write phase is
quadratic; 18k keys is already ~52 s).

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `irmin_mem_rw` — the original fixed-store repetition bench (3000 keys, 80 %
  reads, 20000 mixed ops).

## Notes

- Uses the `irmin` and `irmin.mem` libraries plus `lwt`/`lwt.unix`; built with
  `dune --profile release`, no build quirks.
