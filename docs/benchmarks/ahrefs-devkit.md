# ahrefs-devkit

Devkit is Ahrefs' grab-bag of OCaml utilities. The suite picks four corners of it —
an HTML stream parser, gzip (zlib C bindings), string utilities, IPv4/CIDR parsing —
each an allocation-heavy "GC stress" workload. All build from `ahrefs-devkit.build.sh`
and link the vendored `devkit` library plus its C deps; the system needs `libevent-dev`
and `libcurl4-openssl-dev`.

The **input-size ladder** is on the HTML-stream parser (`devkit_htmlstream`); the other
three are legacy benches (below).

## Ladder

`devkit_htmlstream` is a synthetic 8-part `HtmlStream.parse` GC-stress suite; its
`Sys.argv.(1)` is a **content-scale factor** that multiplies the per-document element
counts and retained-structure sizes (leaving the outer 10-document repetition fixed), so
a bigger factor parses bigger HTML and retains more. Only bounded-cost loops are scaled
(the two super-linear pieces stay fixed) so growth is ~linear; factor 1 reproduces the
frozen bench. Measured on 5.5.0, Ryzen 9 9950X:

| rung | scale | wall | RSS | peak heap | allocated | gc% | max pause |
| --- | --- | --- | --- | --- | --- | --- | --- |
| small | 1 | 7.1s | 0.37 GB | 0.63 GB | 1.65 G w | 5% | 22 ms |
| default | 3 | 19.6s | 1.09 GB | 1.86 GB | 4.84 G w | 5% | 53 ms |
| large | 8 | 50.7s | 2.57 GB | 4.57 GB | 12.3 G w | 5% | 141 ms |

Allocation churn, peak heap and RSS all grow ~7.5×, but major collections barely move
(255 → 342) — retention is mostly transient (per-document `Buffer`s dropped each pass), so
gc% stays a flat ~5%. The distinctive signal is the **max GC pause, 22 → 141 ms**: the large
`String.make` script/style blocks cost a long sweep tail that lengthens with the factor.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `devkit_htmlstream` — the frozen anchor (scale 1) of the ladder above.
- `devkit_stre` — `Stre` string utilities; minor GC + intentional retention (promotion path).
- `devkit_network` — `Network` IPv4/CIDR parsing; minor-heavy, `Int32` boxing, `Hashtbl` NAT tables.
- `devkit_gzip` — `Gzip_io` (zlib C stubs); compute-bound, barely touches the GC.

Each of the three legacy programs takes an in-process repetition count as `Sys.argv.(1)`.

## Notes

- Links against system libevent + libcurl with an explicit rpath.
- `devkit_stre`/`network`/`gzip` are wrapper scripts that exec the real `.exe` in
  `_build-<runtime>`; if you wipe that dir, delete the wrapper output too. `devkit_htmlstream`
  (and its rungs) is a copied standalone binary.
