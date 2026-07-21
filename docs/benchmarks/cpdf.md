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
