# cpdf

cpdf is a command-line PDF toolkit built on the CamlPDF library. The benchmark is
a real end-to-end PDF task: read a file, transform it, write the result. It is
byte-level processing — CamlPDF parses the file into an object map
(`(int, objectdata ref * int) Hashtbl.t`) and rewrites objects — so it mixes minor
allocation, `Bytes` mutation, and `Hashtbl` lookups. Despite being a "pure OCaml"
library, CamlPDF carries C stubs for flate (zlib/miniz), AES, and SHA-2; the flate
stubs are hot when de/re-compressing streams.

## Ladder

Input size = the **document working set**, the copy count `N` passed to the
`cpdf_squeeze` wrapper (`cpdf.build.sh` emits a wrapper that merges N copies of
`PDFReference16.pdf_toobig` and recompresses every stream). CamlPDF holds the whole
merged object map live at once, so the major heap grows ~linearly with N
(`top_heap` tracks RSS). Recompression (`-squeeze`, via the flate C stubs) is what
lifts wall into the standard bands. Measured on OCaml 5.5.0, Ryzen 9 9950X
(`fingerprint.sh` `v=0x400`; olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | copies | wall | RSS | gc% | top_heap | max pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 8 | 7.4s | 0.88 GB | 31.4% | 110M w | 12 ms |
| `_default` | 24 | 18.2s | 1.77 GB | 25.5% | 225M w | 34 ms |
| `_large` | 64 | 57.4s | 3.04 GB | 16.2% | 405M w | 44 ms |

Each rung reaches a strictly bigger live-heap regime (`top_heap` 110 → 405M words,
major cycles 38 → 56, tail pauses growing). gc% **falls** as the document grows
(31 → 16%): a bigger merged PDF spends proportionally more time in flate C
recompression (off-heap CPU that isn't GC), so this is a moderate-GC,
live-heap-driven ladder. A huge band is deferred (128 copies ≈ 2min at ~6 GB).

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`) — four single-document
operations on the reference PDF, each writing to `/dev/null`:

- `cpdf_merge` — merges the PDF with itself (memory-bound, ~5.6s).
- `cpdf_blacktext` — recolors all text to black (~6.8s).
- `cpdf_scale` — scales to A4 landscape 2-up; the long pole (~36s) on page-geometry
  compute, not GC.
- `cpdf_squeeze` — re-compresses object streams (~9s; the operation the ladder scales).

## Notes

cpdf and CamlPDF are manually vendored under `vendor/cpdf-source` and
`vendor/camlpdf` (upstream uses OCamlMakefile, not dune); the build uses
hand-written dune overlays. The C stubs are compiled in via `foreign_stubs` in
`vendor/camlpdf/dune`, so a working C toolchain is required.
