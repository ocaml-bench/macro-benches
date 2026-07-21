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
