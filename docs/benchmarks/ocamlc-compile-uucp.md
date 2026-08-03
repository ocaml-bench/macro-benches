# ocamlc-compile-uucp

The companion to [ocamlc-self-compile](ocamlc-self-compile.md): the same tool — the
runtime-under-test's own `ocamlc` (bytecode) — but a deliberately different-character
workload. It compiles the real [uucp](https://erratique.ch/software/uucp) Unicode
library (56 flat `Uucp_*` modules, stdlib-only, no ppx — it compiles standalone with
zero curation). uucp's data/constant Unicode tables produce a small, **actively-collected**
heap (active major GC, higher promotion, constant/codegen emission) — the opposite of
self-compile's large monotonic heap. That is what lets it carry the compiler's size ladder.

## Ladder

Input size = the **number of uucp replicas** compiled: `ocamlc-compile-uucp.build.sh`
prefix-renames the module set (`Uucp` → `UucpK`) so N copies coexist in one `ocamlc`
invocation. Because the heap is collected, compiling more of it scales the **major-GC
work** (cycles + promotion) at a nearly flat RSS — the cheapest large rung in the suite.
Measured on OCaml 5.5.0, Ryzen 9 9950X (olly, `perf_grp1|re-25|md-2`):

| rung | replicas | wall | RSS | gc% | major GC | promoted | max pause |
| --- | --- | --- | --- | --- | --- | --- | --- |
| small | 3 | 6.0s | 86 MB | 17.1% | 376 | 0.14 G w | 2.3 ms |
| default | 8 | 16.8s | 90 MB | 17.4% | 770 | 0.40 G w | 2.6 ms |
| large | 25 | 57.9s | 115 MB | 17.8% | 1581 | 1.36 G w | 4.2 ms |

Major collections and promotion scale ~linearly with the replica count while RSS stays
~90-115 MB and gc% holds ~17% — a major-GC-throughput ladder, complementary to
self-compile's memory-bound (monotonic-heap) scaling.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `ocamlc_compile_uucp` — the library compiled once (N=1): the data-character fixed
  point (~2s, ~78 MB, ~154 major cycles), opposite of `ocamlc_self_compile`.

## Notes

Builds nothing through dune. Like self-compile, it stages a renamed copy of `ocamlc.opt`
(`<out>_bin`) so running-ng's process filter attaches olly, and pins `OCAMLLIB`.
