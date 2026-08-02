# goblint

Goblint is a static analyser for C, based on abstract interpretation with relational
(apron) domains. This benchmark runs it on one SV-COMP verification task. It is the suite's
second independent C abstract-interpreter (after frama-c) and the reproducer for the OCaml 5
allocation regression tracked in ocaml#13733. It was added to the suite recently.

## What it runs

One program, `goblint`. It analyses `bench.c`, a single SV-COMP task
(`btor2c-lazyMod.vcegar_QF_BV_itc99_b13_p02.c`, a Btor2-to-C translation of a hardware
verification problem) picked as an extreme allocation outlier from ocaml#13733. The input is
tiny, about 5.6 KB, but goblint builds a large analysis state from it and allocates heavily.

The run command comes from the issue and is baked into the wrapper:

```
goblint --conf svcomp.json --sets ana.specification unreach-call.prp \
        --sets exp.architecture 64bit --set pre.cppflags[+] -std=gnu17 bench.c
```

`svcomp.json` is the SV-COMP analysis config (SV-COMP mode on, interval and relational
domains, the autotuner enabled with octagon/congruence/widening thresholds and more).
`unreach-call.prp` is the property being checked: the error location `reach_error()` is
never reachable. `-std=gnu17` is there so GCC 15's C23 `stddef.h` (which defines `nullptr`)
stays parseable by goblint-cil.

The build (`goblint.build.sh`) has two stages. Goblint 2.7.1, goblint-cil 2.0.9 and roughly
60 dependencies are vendored via opam-monorepo (`duniverse/analyzer`, `duniverse/cil`) and
built hermetically by dune. apron is the exception: it is required (the svcomp config and the
autotuner both enable it) but it is not a dune package (it builds with configure/make plus
camlidl), so it cannot join the unified dune build. `scripts/vendor-apron.sh` builds the
camlidl / mlgmpidl / apron chain per-runtime from pinned source into a self-contained prefix,
using only the active compiler plus gcc, ocamlfind and make (no opam, no solver, no repos),
so it works on arbitrary runtimes the same way `duniverse/` does. `goblint.build.sh` then
exposes just that prefix to the otherwise-hermetic build via `OCAMLPATH`.

The output `goblint-<runtime>` is a wrapper script. It puts apron's shared libraries on the
dynamic-loader path (the OCaml side is statically linked, but apron's C stubs are dlopened)
and points goblint's `pre.custom_includes` at the vendored libc / sv-comp / linux stub
directories under `duniverse/analyzer/lib`, because the dune-site resource sites that would
normally hold those are empty in an uninstalled build.

## Knob-A ladder (analysed-program size)

The frozen `goblint` program analyses the fixed #13733 reproducer (~0.2s here — too
short for a macro rung). The `goblint_gen_{small,default,large}` rungs scale the one
thing that grows goblint's working set: the **size of the analysed C program**.
`goblint.build.sh` generates a synthetic Btor2C-style bit-vector state machine —
`N` state variables updated in a `for(;;)` loop via masked bit-vector logic, in the
same shape as `bench.c` — and analyses it with the *same* `svcomp.json` (interval +
octagon/apron) config. A bigger `N` means more variables tracked and more program
points, so goblint's constraint solver does proportionally more fixpoint work. The
values are masked so the analysis reaches a fixpoint and proves every assert safe
(`SV-COMP result: true`), i.e. each rung does the full analysis. Measured on OCaml
5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly from `perf_grp1|re-25|md-2`):

| rung | N | wall | gc% | RSS | allocated | minor GC | major GC | top_heap |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `_small` | 100 | 4.3s | 22% | 77 MB | 3.83 G w | 14645 | 41 | 5.9 M |
| `_default` | 165 | 16.3s | 27% | 120 MB | 14.0 G w | 53525 | 67 | 11.2 M |
| `_large` | 240 | 46.6s | 34% | 186 MB | 39.5 G w | 150770 | 97 | 19.5 M |

This is the suite's purest **allocation-churn** ladder — exactly goblint's #13733
signature. The octagon domain is O(N²), so wall and allocation grow super-linearly:
`allocated_words` climbs 3.83 → 39.5 G (10×) and minor collections 15k → 151k while
peak RSS stays modest (77 → 186 MB). The live set does grow (top_heap 5.9 → 19.5 M
words, major cycles 41 → 97), but the headline signal is **allocated_words** — read
this ladder by allocation volume, not RSS. It is a pure on-heap counterpoint to
pplacer's off-heap GSL footprint, and scales up the same 5.x GC/allocation regression
(ocaml#13733, sibling of frama-c's #11733) that the frozen reproducer freezes. A huge
band is deferred (N≈340 would be ~min-scale).

## What it stresses

High allocation and minor-GC churn: roughly 1.3 GB allocated to analyse a 5.6 KB input, with
a peak RSS of only about 48 MB. Almost all of it is churn, not live set. Beyond that:

- Hash-consing in the analysis state.
- The apron relational domains, which go through C / GMP FFI.
- Recursive-variant allocation for the CIL AST.

## Reading the results

Rough baseline numbers:

- Wall around 0.2-1s on modern hardware.
- About 1.3 GB allocated, peak RSS around 48 MB.

The headline signal is total allocation. The documented ocaml#13733 regression (Goblint's
roughly 4x CPU and allocation increase from OCaml 4.14 to 5.x) shows up as about 4x more
allocated bytes for identical analysis output. Goblint and frama-c are both CIL-based C
analysers and the two issues (ocaml#13733 and ocaml#11733) are linked, so if
`allocated_bytes` / `wall_time` move here and on `frama_c_eva_*` together, suspect a shared
5.x GC/allocation cause; movement on goblint alone points at its own hash-consing or solver
path.

## Notes

apron is genuinely required here, which is what makes goblint the fiddliest build in the
suite. Five vendored-source patches are needed to build on a modern toolchain: `goblint.h`
(GCC 14+/C23), a `cpu` autoconf `config.h`, a `bare_encoding` source-install fix, a
`json-data-encoding` fork re-alignment to `Yojson.Safe.t`, and a first-class-module
annotation in `control.ml` for OCaml 5.5 and up.

Verified building and running from a clean slate on 5.4.1 and the July trunk baseline
`e53a0322` (2026-07-21). It also builds on the 5.5 beta `d8bb46c` and earlier trunk from
`fb4f451` onward; the late-May `cfb30145` snapshot hit a since-fixed `Ctype.Unify` compiler
bug (the same one worked around for dolmen), so anything before that fix will not build. The
other runtimes (mmtk, gc-pacing) are not currently validated for goblint. Note that goblint's
own opam metadata carries an advisory against benchmarking it on OCaml 5, which is exactly the
regression this benchmark is here to measure.
