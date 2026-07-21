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
