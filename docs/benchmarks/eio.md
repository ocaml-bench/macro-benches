# eio

Eio is OCaml 5's effects-based concurrency and I/O library. This benchmark puts its
scheduler under producer/consumer load — fibers pushing data through bounded streams
while other fibers pull it back out — built on `Effect.perform` and deep effect
handlers. It is a single-domain benchmark and the suite's cleanest signal for
effects and fiber scheduling.

## Ladder

Input size = the **degree of concurrency** (`n_pairs`), the axis an effects
scheduler exists for. A driver (`eio_conc_bench.ml`) runs `n_pairs` independent
producer/consumer fiber pairs, each pair on its *own* bounded stream, with a fixed
20000 items per fiber. All `2·n_pairs` fibers are alive at once, so the working set
— the parked fibers' continuations plus data buffered across the streams — grows
~linearly with `n_pairs` (per-pair streams keep scheduling ~linear, whereas one
shared stream's O(n) waiter queue makes wall blow up super-linearly). Measured on
OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly gc%/pause from
`perf_grp1|re-25|md-2`):

| rung | n_pairs | wall | RSS | gc% | max pause |
| --- | --- | --- | --- | --- | --- |
| `small` | 3000 | 5.7s | 0.69 GB | 61.9% | 6.5 ms |
| `default` | 9000 | 17.1s | 1.99 GB | 62.6% | 36 ms |
| `large` | 21000 | 40.6s | 4.96 GB | 63.0% | 76 ms |

This is a promotion-bound, live-set concurrency ladder: the buffered/in-flight data
is genuinely retained (top_heap 84 → 619 M words, RSS 0.69 → 4.96 GB), the promotion
fraction is high and flat (~0.85), so gc% sits at a heavy ~62% (second only to
liq_video_frames in the suite) and pauses lengthen with the live heap (6.5 → 76 ms).
It is the effects-scheduler counterpart to the allocation-churn (goblint) and
off-heap-footprint (pplacer) ladders. A huge band is deferred (`n_pairs` ~45000
would be ~min-scale at ~10 GB).

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `eio_fiber_stream` — the original throughput bench: a few fibers stream many items
  through one shared bounded stream (~9 MB constant live set, data discarded as fast
  as it is made).

## Notes

- Requires OCaml 5.2 or newer (Eio 1.x and effects). Built with `dune --profile
  release`; nothing unusual in the build glue.
