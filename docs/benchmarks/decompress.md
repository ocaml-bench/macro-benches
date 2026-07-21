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

The build script copies the `.exe` out directly, so the suite drives it with
the source defaults (64 iterations of 32 KB). The README describes this as
"decompresses 32 KB 64 times"; the loop actually does a compress and a
decompress each round, over freshly generated random text.

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
