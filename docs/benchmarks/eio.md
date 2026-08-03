# eio

Eio is OCaml 5's effects-based concurrency and I/O library. This benchmark
(`eio_fiber_stream`) puts it under a simple but heavy producer/consumer load: a
pile of fibers push data through a bounded stream while another pile pulls it
back out.

## What it runs

One program, `eio_fiber_stream` (built from `eio_bench.ml`). It spawns 4
producer fibers and 4 consumer fibers on a single domain. Each producer pushes
15 million tuples of the form `(id, i, String.make 64 c)` onto a bounded
`Eio.Stream` with capacity 1024; the consumers pop them until the whole batch
is drained.

That works out to 60 million items total (4 producers times 15M each), and
roughly 3.6 GB of fresh 64-byte strings allocated and immediately thrown away.
The bounded stream (capacity 1024) forces producers and consumers to interleave:
a full stream parks the producer, an empty one parks the consumer, so every
push and pop tends to bounce through the scheduler.

There are no command-line arguments. The counts are compiled in. The program
prints how many items it processed and the wall time.

## Knob-A ladder (concurrency degree)

`eio_fiber_stream` is a *throughput* benchmark: a handful of fibers push a huge
number of items through one shared stream, so its live set is tiny (~9 MB) and
constant — scaling its item count is pure repetition (Knob B). The
`eio_conc_{small,default,large}` rungs scale the axis an effects scheduler exists
for: the **degree of concurrency**. A separate driver (`eio_conc_bench.ml`) runs
`n_pairs` (the arg) independent producer/consumer fiber pairs, each pair on its
*own* bounded stream, with a fixed 20000 items per fiber. All `2 * n_pairs` fibers
are alive at once, so the working set — the parked fibers' effect continuations
plus the data buffered across all the streams — grows ~linearly with `n_pairs`.
Giving each pair its own stream is deliberate: on a single shared stream the O(n)
waiter queue makes wall blow up super-linearly under contention, whereas per-pair
streams keep scheduling ~linear so wall tracks the working set. Measured on OCaml
5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly gc%/pause from
`perf_grp1|re-25|md-2`):

| rung | n_pairs | wall | gc% | RSS | top_heap | major GC | p99.9 | max pause |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `_small` | 3000 | 5.7s | 61.9% | 0.69 GB | 84 M w | 97 | 6.1 ms | 6.5 ms |
| `_default` | 9000 | 17.1s | 62.6% | 1.99 GB | 256 M w | 107 | 9.0 ms | 36 ms |
| `_large` | 21000 | 40.6s | 63.0% | 4.96 GB | 619 M w | 117 | 12.6 ms | 76 ms |

Unlike the frozen throughput bench (whose data is discarded as fast as it is made),
here the buffered/in-flight data across `n_pairs` streams is genuinely **retained**
for the run: `top_heap` grows 84 → 619 M words (RSS 0.69 → 4.96 GB), and the
promotion fraction is high and flat (~0.85), so gc% sits at a heavy ~62% (the
minor→major copy path plus major collection dominate — second only to
liq_video_frames in the suite). Pauses lengthen with the live heap (max 6.5 → 76 ms).
So this is a promotion-bound, live-set concurrency ladder — the effects-scheduler
counterpart to the allocation-churn (goblint) and off-heap-footprint (pplacer)
ladders. Per-fiber work (20000 items) is held fixed; only `n_pairs` varies. A huge
band is deferred (`n_pairs` ~45000 would be ~min-scale at ~10 GB).

## What it stresses

- Effects and the OCaml 5 scheduler. Eio's `Stream.add`/`take` and
  `Fiber.both`/`all` are built on `Effect.perform` and deep effect handlers, so
  a high volume of stream traffic means a high volume of effect performs and
  fiber switches.
- The minor GC and promotion. Sixty million short-lived strings is a lot of
  minor-heap churn. Because producers can run ahead of consumers up to the
  stream's capacity, some of that data survives long enough to be promoted, so
  this leans on the minor-to-major copy path too.
- Atomics, indirectly, through the stream's bounded-queue synchronization.

The one thing it obtains but does not use is the domain manager: it grabs
`Stdenv.domain_mgr` and then never spawns a second domain. This is a
single-domain benchmark.

## Reading the results

Expect a wall time of around 6s. GC is promotion-heavy: roughly 10% of
allocated data gets promoted, with a fairly high ratio of major to minor
collections for this suite (on the order of thousands of minor collections and
over a thousand major ones). RSS is modest since the working set is small and
the data is discarded as fast as it is made.

This is the suite's cleanest signal for effects and fiber scheduling. If
`eio_fiber_stream` moves and none of the allocation-heavy benchmarks do, look
at effect-handler internals or the fiber-stack path. If it moves along with all
the promotion-heavy benchmarks, suspect the minor-to-major copy path instead.

## Notes

Requires OCaml 5.2 or newer (it needs Eio 1.x and effects). Built with
`dune --profile release` into a per-runtime build directory; nothing unusual in
the build glue.
