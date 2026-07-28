# yojson

yojson is a widely used JSON library for OCaml. This benchmark parses a JSON file
into yojson's tree type and serializes it back, many times over, to exercise the
parser, the tree it builds, and the GC that has to clean up after each round.

## What it runs

One program, `ydump_repeat`, built from `benchmarks/yojson/ydump_repeat.ml`.

It takes an iteration count (`argv.1`) and a document (`argv.2`), then loops N times:

- `Yojson.Safe.from_string data` to parse, then
- `Yojson.Safe.to_string json` to serialize the result back to a compact string.

The output of each round is discarded. The document argument is dual-purpose: **if it
names an existing file it is read** (legacy behaviour — the `ydump_repeat` bench passes
`1000` and the ~670 KB `sample.json`); **otherwise it is parsed as an integer record
count and a JSON document of that many records is generated in-process** (see the
Knob-A ladder below), so the size rungs need no vendored or generated files.

The parsed value is yojson's recursive variant type, `` `Assoc of (string * t) list ``,
`` `List of t list ``, and so on, so each parse rebuilds a full nested tree.

## Knob-A ladder (document size)

Knob A is the **JSON document size**, driven by `argv.2` as a generated record count
(iterations pinned to 1 — pure working-set, not repetition). Each record is a small
nested object (`id`, `name`, `value`, a 3-element `tags` array, `active`, a nested
`{x,y}`), ~128 bytes, so the document — and the memory-heavy Yojson tree it parses into
— grow with the count. Generating in-process avoids giant vendored files. Measured on
OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh`, `v=0x400`):

| rung | records | doc size | wall | RSS | live heap (top_heap_words) | promo frac |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 2M | 257 MB | 5.5s | 3.25 GB | 448 M | 0.28 |
| `_default` | 6M | 771 MB | 16.3s | 10.0 GB | 1.32 G | 0.28 |
| `_large` | 12M | 1.54 GB | 32.7s | 20.2 GB | 2.64 G | 0.28 |

This is a promotion-heavy footprint ladder: the parsed tree is large and lives across
the parse, so ~28% of allocation is promoted (the parse-and-promote path), and RSS grows
~linearly with the document. The Yojson tree is memory-heavy (boxed variants + string
nodes + association lists), so RSS is ~13x the document size — `_large` is RAM-capped at
20 GB / ~33s, just under the 1-3 min band; a huge band is deferred (tracked separately).

olly gc-profile (running-ng `perf_grp1|re-25|md-2`, 5.5.0, one invocation; olly wall
exceeds the `v=0x400` wall from attach + ring overhead on the multi-GB runs):

| rung | wall | gc% | gc_time | max_rss_kb_excl_ring | max pause | p99.9 pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 5.8s | 28.9% | 1.68s | 3.10 GB | 161 ms | 14.9 ms |
| `_default` | 19.0s | 33.6% | 6.37s | 9.59 GB | 209 ms | 36.0 ms |
| `_large` | 41.6s | 39.6% | 16.5s | 19.25 GB | 424 ms | 63.7 ms |

yojson has the **largest GC pauses in the whole suite** — up to ~424 ms at `_large`
(p99.9 ~64 ms) — because each iteration builds and then discards a multi-GB tree of tiny
boxed nodes (`` `Assoc ``/`` `List ``/strings), and marking/collecting that tree is a huge
unit of GC work. gc% also rises with size (29% → 40%) as more of each iteration is spent
promoting into and scanning the growing major heap. So this ladder is the primary signal
for **promotion throughput and major-GC pause latency on a large pointer-dense tree**.
(Note: olly reports `promoted_pct` ~3.3%, which is the true ~28% promotion fraction divided
by 8 — a symptom of the olly minor-allocation-counter units bug; the `v=0x400` fraction of
0.28 in the table above is the correct one.)

There is a second, unrelated source in this directory (`ydump.ml`, the yojson CLI
pretty-printer). It is not what this benchmark runs.

## What it stresses

This is a parse-and-promote workload. Every iteration allocates a complete JSON
tree of recursive-variant blocks plus a string for each key and string-valued node.
Unlike a pure minor-churn benchmark, the tree lives long enough within an iteration
to get promoted, so the major GC does real work here. File I/O happens only once at
startup, so it is not part of the measured loop.

## Reading the results

Expect wall time around 5.5s with a low gc_overhead near 4.5%. The interesting
number is the major-to-minor ratio: it is high (the README observed roughly 1654
major / 2541 minor, about 65%), which tells you promotion is a real part of the
cost, not just minor allocation.

A regression here that also shows up on other AST-shaped, promotion-heavy workloads
points at the minor-to-major copy path. A regression only here points at something
yojson-specific in the parser or serializer.

## Notes

Built from the monorepo with `dune build --profile release
benchmarks/yojson/ydump_repeat.exe`, against the vendored `yojson` under
`duniverse/`. No system libraries or FFI involved.
