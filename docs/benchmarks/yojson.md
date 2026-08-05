# yojson

yojson is a widely used JSON library for OCaml. This benchmark parses a JSON document
into yojson's recursive-variant tree (`` `Assoc ``/`` `List ``/strings) and serializes
it back, so it exercises the parser, the memory-heavy tree it builds, and the major GC
that promotes and then collects that tree.

## Ladder

Input size = the **JSON document size**, driven by `argv.2` as a generated in-process
record count (iterations pinned to 1 — pure working set, not repetition). Each record is
a small nested object (~128 bytes), so the document and the tree it parses into grow with
the count; ~28% of allocation is promoted at every rung (the parse-and-promote path). The
tree is boxed and pointer-dense, so RSS is ~13x the document size. Measured on 5.5.0,
Ryzen 9 9950X (wall/RSS from `fingerprint.sh` `v=0x400`; gc%/pause from olly
`perf_grp1|re-25|md-2`):

| rung | records | doc size | wall | RSS | gc% | max pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 2M | 257 MB | 5.5s | 3.25 GB | 28.9% | 161 ms |
| `_default` | 6M | 771 MB | 16.3s | 10.0 GB | 33.6% | 209 ms |
| `_large` | 12M | 1.54 GB | 32.7s | 20.2 GB | 39.6% | 424 ms |

yojson has the **largest GC pauses in the whole suite** — up to ~424 ms at `_large`
(p99.9 ~64 ms) — because marking and collecting a multi-GB tree of tiny boxed nodes is a
huge unit of GC work. gc% also rises with size (29% → 40%) as more of each run is spent
promoting into and scanning the growing major heap. So this ladder is the primary signal
for promotion throughput and major-GC pause latency on a large pointer-dense tree.
`_large` is RAM-capped at 20 GB / ~33s; a huge band is deferred.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `ydump_repeat` — the original fixed-doc repetition bench (1000x the ~670 KB
  `sample.json` file).

## Notes

- Built against the vendored `yojson` under `duniverse/`; no system libraries or FFI.
- olly reports `promoted_pct` ~3.3% here — the true ~0.28 fraction over 8, a symptom of
  the olly minor-allocation-counter units bug; the `v=0x400` fraction is the correct one.
- A second, unrelated source (`ydump.ml`, the yojson CLI pretty-printer) lives in this
  directory but is not what this benchmark runs.
