# ahrefs-devkit

Devkit is Ahrefs' open-source grab-bag of OCaml utilities: string helpers, IPv4/CIDR
parsing, an HTML stream parser, gzip via zlib C bindings, and a lot more. These four
benchmarks each pick one corner of Devkit and hammer it with allocation-heavy workloads.
They were originally written as "GC stress" tests, and the source comments still say so,
but in practice only some of them actually lean on the collector (see each subsection).

All four build from the same script (`ahrefs-devkit.build.sh`) and link against the
vendored `devkit` library plus its C dependencies (libevent, libcurl). The system needs
`libevent-dev` and `libcurl4-openssl-dev` installed.

## What it runs

Four separate executables, one per Devkit area. Three of them (`gzip`, `stre`,
`network`) read an iteration count from `Sys.argv.(1)` and run their eight internal
sub-benches that many times in one process, so a short workload can be scaled up until
`olly` has enough to observe. The build script wraps those three in a tiny shell script
that just execs the real binary with the argument passed through (default 1 if none is
given). `htmlstream` is different: it does not read argv at all, runs each sub-bench a
fixed number of times, and is copied out as a plain standalone binary.

| Program | Devkit area | Iteration control | Rough profile |
|---|---|---|---|
| `devkit_gzip` | `Gzip_io` (zlib C bindings) | `Sys.argv.(1)`, default 1 | compute-bound, ~10s |
| `devkit_stre` | `Stre` string utilities | `Sys.argv.(1)`, default 1 | minor GC + retention, ~14s |
| `devkit_network` | `Network` IPv4/CIDR parsing | `Sys.argv.(1)`, default 1 | minor-heavy, ~17s |
| `devkit_htmlstream` | `HtmlStream` parser | none (fixed internal loops) | minor + retention, ~25s |

### devkit_gzip

Eight sub-benches built around `Devkit.Gzip_io`: small-buffer compression storms,
large-block compression, streaming chunk-by-chunk compress/decompress, mixed-size
patterns cached in a `Hashtbl`, concurrent-style stream pools, header and checksum
processing, buffer recycling, and multi-stage compression pipelines. Each iteration
compresses generated test data at various zlib levels and decompresses it back,
asserting round-trip correctness.

Despite the "GC stress" label in the source, this one is compute-bound. The real work
happens inside zlib in C, over reused `Bytes` buffers, so GC pressure stays low.

### devkit_stre

Eight sub-benches over `Devkit.Stre`, the string-utility module: split storms with
`Stre.nsplitc`, substring slicing with `Stre.slice` and `Stre.from_to`, pattern
processing over multi-line text, concatenation chains with `^`, enum-based processing
via extlib's `Enum`, mixed-size string allocations into a `Hashtbl`, buffered string
building, and deep transformation chains that repeatedly slice and rejoin.

The sub-benches deliberately keep prefixes of their `retained_*` lists modulo small
primes, so a fraction of the allocated strings survive long enough to be promoted. That
is what gives this one its noticeable major-collection count.

### devkit_network

Eight sub-benches over `Devkit.Network`: IPv4 address parsing (10000 addresses per
pass), CIDR subnet calculations with bitwise ops, IP-range enumeration, mixed-format
parsing, NAT-table operations backed by two `Hashtbl`s, IP sorting and grouping,
broadcast/network-boundary calculations, and complex CIDR-matching operations. The
internal IPv4/CIDR parser is ragel-generated but pure OCaml (no FFI here).

Lots of `Int32` values flow through this (IPv4 addresses are 32-bit), so it is a good
probe for boxed-int handling as well as the minor allocator.

### devkit_htmlstream

Eight sub-benches over `Devkit.HtmlStream`. Each one builds a large HTML document (1-5 MB)
into a `Buffer`, then parses it with `HtmlStream.parse`: small-string storms, big
attribute lists, large script/style blocks, a "morphing heap" phase mix, fragmentation
stress, a generational-hypothesis-violation pattern, variable allocation rates, and a
reference-graph builder. Several sub-benches retain a prime-modulo subset of the parsed
elements, which pushes some allocations into the major heap.

This is the longest of the four on its own, which is why it does not bother with an
argv iteration loop.

## What it stresses

- `devkit_gzip`: zlib C stubs and codegen for tight `Bytes`-mutation loops. Barely
  touches the GC. Each `Gzip_io` channel wraps a zlib `z_stream` custom block.
- `devkit_stre`: the string allocator and the minor-to-major promotion path, thanks to
  the intentional retention. Heavy `String.sub` / `String.concat` / `Hashtbl` traffic.
- `devkit_network`: the minor GC and `Int32` boxing, plus `Hashtbl` for the NAT tables.
  Almost no promotion.
- `devkit_htmlstream`: the `Buffer` allocator (large documents built then discarded) and
  a moderate amount of promotion from the retained-element pattern.

## Reading the results

Rough baselines from earlier runs:

| Program | wall | gc_overhead | minor / major |
|---|---|---|---|
| `devkit_gzip` | ~10s | ~1% | very low |
| `devkit_stre` | ~14s | ~5.5% | ~7700 / ~3000 |
| `devkit_network` | ~17s | ~4.5% | ~10400 / ~74 |
| `devkit_htmlstream` | ~25s | ~3.3% | ~3500 / ~150 |

For `devkit_gzip`, GC changes should barely move it. If it moves, look at compiler
codegen (flambda especially) or the zlib FFI path, not the collector. For `devkit_stre`,
a regression that does not show up on a pure-minor benchmark points at the promotion
path rather than plain minor allocation. For `devkit_network`, movement points at
`Int32`/boxed-int handling, small-integer compare codegen, or hashtable performance.
For `devkit_htmlstream`, it pairs with other `Buffer`-heavy workloads: if only this one
moves, suspect the `HtmlStream` parser itself.

## Notes

- The build links against system libevent and libcurl with an explicit rpath; those
  dev packages must be present.
- `devkit_gzip`, `devkit_stre`, and `devkit_network` end up as small wrapper scripts
  that exec the real `.exe` inside the per-runtime `_build-<runtime>` tree. If you delete
  a `_build-<runtime>` directory, delete the wrapper output too, otherwise running-ng
  thinks the binary is already built and the wrapper fails at run time. `devkit_htmlstream`
  is a copied standalone binary and does not have this issue.
- These are accumulate-in-one-process workloads when scaled via `Sys.argv.(1)`, so they
  need a large enough `runtime_events` ring (the suite convention is `re-25`, a 32 MB
  ring). Too small a ring drops events and corrupts `wall_time`.
