# decompress

Decompress is a pure-OCaml zlib/DEFLATE implementation (no C), built on
`Bigstring` I/O buffers. This benchmark runs a compress-then-decompress round trip
over random, incompressible data, so it is one of the few allocation-shape
benchmarks in the suite with no FFI in the hot path — the suite's compute-bound
control.

## Ladder

Input size = the **payload size** (`argv.2`, bytes), with iterations pinned to 1,
so the ladder is pure working-set, not repetition. A bigger payload grows the input
string and the compress/uncompress output buffers, so RSS and the live heap grow
~linearly with it. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh`
`v=0x400` for wall/RSS; olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | payload | wall | RSS | gc% | max pause |
| --- | --- | --- | --- | --- | --- |
| `small` | 80 MB | 4.9s | 0.5 GB | 0.8% | 1.7 ms |
| `default` | 256 MB | 15.9s | 1.4 GB | 0.8% | 4.4 ms |
| `large` | 1 GB | 62.9s | 5.7 GB | 0.9% | 21 ms |

gc% sits at ~0.8% at every size, far lower than any other laddered tool, so this
ladder isolates codegen / DEFLATE-loop performance from GC almost entirely — use it
to catch pure compute/codegen regressions, and as a Bigstring-alloc cross-check
against owl (shared Bigstring use, no FFI here). The major-collection count stays
pinned (~57) across all rungs, and the p99.9 pause is negligible (0.03 ms) — the
max-pause column is a single transient (big-buffer free), not a latency signature.
Read footprint from the `/usr/bin/time` RSS above (one olly pass read a one-off
10.7 GB at `_large` that did not reproduce). A huge band is deferred.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `test_decompress` — the original fixed-payload repetition bench (64 iterations of
  a 512 KB payload of freshly generated random text).

## Notes

- Pure OCaml, so it also builds under OxCaml (along with menhir and zarith).
- The input is deterministic (`Random.init 42`), so run-to-run variation is from the
  runtime, not the data.
