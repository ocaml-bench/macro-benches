# yojson

yojson is a widely used JSON library for OCaml. This benchmark parses a JSON file
into yojson's tree type and serializes it back, many times over, to exercise the
parser, the tree it builds, and the GC that has to clean up after each round.

## What it runs

One program, `ydump_repeat`, built from `benchmarks/yojson/ydump_repeat.ml`.

It takes an iteration count and a file path (the suite passes `1000` and
`benchmarks/yojson/sample.json`; the source default for the count is `10`). It reads
the whole file once into a string, then loops N times doing:

- `Yojson.Safe.from_string data` to parse, then
- `Yojson.Safe.to_string json` to serialize the result back to a compact string.

The output of each round is discarded. `sample.json` is about 670 KB.

The parsed value is yojson's recursive variant type, `` `Assoc of (string * t) list ``,
`` `List of t list ``, and so on, so each parse rebuilds a full nested tree.

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
