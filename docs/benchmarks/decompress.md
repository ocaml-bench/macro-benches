# decompress

Decompress is a pure-OCaml zlib/DEFLATE implementation (no C), built on
`Bigstring` I/O buffers. This benchmark exercises a compress-then-decompress
round trip in a loop, so it is one of the few allocation-shape benchmarks in
the suite with no FFI in the hot path.

## What it runs

The program is `test_decompress` (`benchmarks/decompress/test_decompress.ml`),
using the `decompress.zl`, `bigstringaf`, and `checkseum.ocaml` libraries.

It first builds a fixed 32 KB string of random lowercase letters (seeded with
`Random.init 42`, so it is deterministic). Then, for each iteration, it
compresses that string at level 3 and decompresses the result back. Both
directions reuse their windows, queues, and Bigstring I/O buffers, which are
allocated once per call.

Two arguments, both optional:

- `Sys.argv.(1)`: iteration count (default 64).
- `Sys.argv.(2)`: input size in bytes (default 32 * 1024 = 32 KB).

The build script copies the `.exe` out directly. The legacy `test_decompress` bench
drives it with `64 524288` (64 iterations of a 512 KB payload) — this is the Knob-B
(repetition) bench. The loop does a compress and a decompress each round, over
freshly generated random text.

## Knob-A ladder (payload size)

Knob A is the **payload size** (`argv.2`, bytes), read straight from the argument, with
iterations pinned to 1 — so the ladder is pure working-set, not repetition. A bigger
payload grows the input string and the compress/uncompress output buffers, so RSS and the
live heap grow ~linearly with it. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh`,
`v=0x400`):

| rung | payload | wall | RSS | live heap (top_heap_words) | promo frac |
| --- | --- | --- | --- | --- | --- |
| `_small` | 80 MB | 4.9s | 0.5 GB | 70 M | 0.0005 |
| `_default` | 256 MB | 15.9s | 1.4 GB | 184 M | 0.0005 |
| `_large` | 1 GB | 62.9s | 5.7 GB | 734 M | 0.0005 |

This is a compute + Bigstring-allocation ladder: promotion is near zero (~0.05%) and gc% is
low (the DEFLATE state machines dominate wall). The RSS/live-heap growth is the shape signal.
Notably the **major-collection count stays pinned (~57) across all rungs** — the number of
Bigstring `io_buffer_size` custom blocks is fixed regardless of payload, so it is the
*payload string + output `Buffer`* that grows RSS, not more major cycles. A huge band is
deferred (tracked separately). (Data is random/incompressible, as in the original bench.)

olly gc-profile (running-ng `perf_grp1|re-25|md-2`, 5.5.0, one invocation):

| rung | wall | gc% | gc_time | max_rss_kb_excl_ring | max pause | p99.9 pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 5.0s | 0.8% | 0.04s | 0.55 GB | 1.7 ms | 0.03 ms |
| `_default` | 16.0s | 0.8% | 0.13s | 1.37 GB | 4.4 ms | 0.03 ms |
| `_large` | 64.4s | 0.9% | 0.59s | 10.7 GB* | 21 ms | 0.03 ms |

decompress is the suite's **compute-bound control**: gc% sits at ~0.8% at every size, far
lower than any other laddered tool, so it isolates codegen / DEFLATE-loop performance from
GC almost entirely. The p99.9 pause is negligible (0.03 ms) — the max-pause column is a
single one-off (the transient promotion / big-buffer free), not a latency signature. So use
this ladder to catch pure compute/codegen regressions, and as a Bigstring-alloc cross-check
against owl (shared Bigstring use, no FFI here).

\* Footprint note: on one olly pass `max_rss_kb_excl_ring` read ~10.7 GB at `_large`, ~2x the
ring-free `/usr/bin/time` peak (5.74 GB). This did **not** reproduce: a repeat olly run of the
same rung reported 5.74 GB (correct), four clean `/usr/bin/time` runs are a deterministic
5.47 GB, and the ring alone (`e=25,d=2`, no olly) is 5.47 GB — so the 10.7 GB was a one-off
sampling anomaly, not a systematic olly-RSS bug or workload variance (olly's `excl_ring`
matched `/usr/bin/time` within ~5 % on every other laddered tool). Root cause of the single
outlier is unidentified (likely a transient smaps read during the back-to-back rung sequence).
Use the `/usr/bin/time` RSS in the ladder table as the footprint figure regardless.

## What it stresses

- Promotion. It looks compute-bound but the major:minor collection ratio is
  high (around 50%): the reused Bigstring buffers stay put, but the small
  per-chunk state that the DEFLATE state machines allocate gets promoted each
  round.
- Bigstring buffers. The bulk data lives off-heap, but the buffer headers
  live on the OCaml heap. This is where "Bigstring header allocation" shows
  up as a suspect.
- Pure-OCaml state machines. `De.Lz77.make_window`, `De.Queue.create`, and
  the encode/decode loops do small-block allocation per chunk, with no C
  underneath.

## Reading the results

Expect wall time around 5s with GC overhead near 2.4%. That low overhead is
what makes it look compute-bound, but the promotion ratio is the thing to
watch.

Because it shares Bigarray/Bigstring use with owl but has no FFI, it is a
useful cross-check: movement here without matching movement in owl points
away from a general Bigarray-finalisation or stub problem and toward Bigstring
header allocation or the pure-OCaml promotion path specifically.

## Notes

- Pure OCaml, so it also builds under OxCaml (along with menhir and zarith).
- The input is deterministic (fixed seed), so run-to-run variation is from
  the runtime, not the data.
