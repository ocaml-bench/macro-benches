# cpdf

cpdf is a command-line PDF toolkit built on the CamlPDF library. This benchmark runs
four different cpdf operations over one large reference PDF, so each variant is a
real end-to-end PDF processing task: read the file, do the transformation, write the
result.

## What it runs

All four variants build the same binary from `vendor/cpdf-source`
(`cpdfcommandrun.exe`) and run it against `benchmarks/cpdf/PDFReference16.pdf_toobig`
(about 8.7 MB). Every variant writes its output to `/dev/null`.

| Variant          | What it does                          | Command                                        |
|------------------|---------------------------------------|------------------------------------------------|
| `cpdf_merge`     | Merges the PDF with itself            | `-merge <pdf> <pdf> -o /dev/null`              |
| `cpdf_blacktext` | Recolors all text to black            | `-blacktext <pdf> -o /dev/null`                |
| `cpdf_scale`     | Scales to A4 landscape, 2-up layout   | `scale-to-fit a4landscape -twoup <pdf> -o /dev/null` |
| `cpdf_squeeze`   | Re-compresses object streams          | `-squeeze <pdf> -o /dev/null`                  |

There is also a smaller `metro_geo.pdf` (about 1.6 MB) in the directory; the four
variants above do not use it.

## Knob-A ladder (document working set)

The four variants above are single-document anchors. The
`cpdf_squeeze_{small,default,large}` rungs add a working-set ladder on top of the
`cpdf_squeeze` operation: `cpdf.build.sh` emits a wrapper (for any output whose name
contains `cpdf_squeeze_`) that **merges N copies** of `PDFReference16.pdf_toobig` and
recompresses every stream, with N — the copy count — passed as the single argument
(8 / 24 / 64). Merging N copies is the Knob-A axis: CamlPDF holds the whole merged
object map live at once, so the OCaml major heap grows ~linearly with N (`top_heap`
tracks RSS almost exactly). Recompression (`-squeeze`, via the flate C stubs) is what
lifts wall time into the standard bands — merge alone is memory-bound and tops out
around 17s. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly
gc%/pause from `perf_grp1|re-25|md-2`):

| rung | copies | wall | gc% | RSS | top_heap | minor GC | major GC | p99.9 | max pause |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `_small` | 8 | 7.4s | 31.4% | 0.88 GB | 110M w | 2650 | 38 | 4.4 ms | 12 ms |
| `_default` | 24 | 18.2s | 25.5% | 1.77 GB | 225M w | 5347 | 45 | 7.1 ms | 34 ms |
| `_large` | 64 | 57.4s | 16.2% | 3.04 GB | 405M w | 10788 | 56 | 10.9 ms | 44 ms |

Each rung reaches a strictly bigger live-heap regime: `top_heap` 110 → 405M words
(~0.88 → 3.24 GB, matching RSS), major cycles 38 → 56, and tail pauses grow with the
heap (p99.9 4.4 → 10.9 ms, max 12 → 44 ms). Note gc% **falls** as the document grows
(31 → 16%): a bigger merged PDF spends proportionally more time in flate C
recompression (off-heap CPU that isn't GC), so this is a moderate-GC, live-heap-driven
ladder — the opposite end of the spectrum from liq_video_frames' pacer-bound 80-95%.
A huge band is deferred (128 copies would be ~2min at ~6 GB).

## What it stresses

This is byte-level PDF processing. CamlPDF parses the file into an object map (a
`(int, objectdata ref * int) Hashtbl.t`), then walks and rewrites objects. So you
get a mix of minor allocation, `Bytes` mutation on the raw object data, and
`Hashtbl` lookups against the object map.

Contrary to what you might expect from a "pure OCaml" library, CamlPDF is not FFI-free.
It carries C stubs for flate (zlib/miniz) compression, AES, and SHA-2. The flate
stubs matter here in particular: decoding compressed streams on the way in and, for
`cpdf_squeeze`, re-compressing them on the way out both go through C.

I/O is part of the cost too, since the multi-megabyte input is read at startup.

## Reading the results

Walls differ a lot between variants. Rough numbers: merge around 5.6s, blacktext
around 6.8s, squeeze around 9.1s, and scale around 35.7s. gc_overhead sits in the
medium 20-40% range, with low minor-collection counts (a few thousand) and low major
counts (tens). `cpdf_scale` is the long pole because its page-geometry work is
genuinely more compute-heavy than the others, not because of GC.

A regression across all four points at the shared paths: `Bytes` allocation and
mutation, the object-map `Hashtbl`, or the flate C stubs. A regression on one
variant alone points at that specific operation.

## Notes

cpdf and CamlPDF are manually vendored under `vendor/cpdf-source` and
`vendor/camlpdf` because upstream uses OCamlMakefile rather than dune; the build
uses hand-written dune overlays. The C stubs (`flatestubs.c`, `stubs-aes.c`,
`stubs-sha2.c`, and friends) are compiled in via `foreign_stubs` in
`vendor/camlpdf/dune`, so a working C toolchain is required to build this.
