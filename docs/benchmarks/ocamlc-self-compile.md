# ocamlc-self-compile

`ocamlc` is OCaml's bytecode compiler, and it is itself a real OCaml program.
This benchmark points the runtime-under-test's own `ocamlc` at a large generated
source file and times how long it takes to compile it. So the thing being measured
is the runtime executing a genuine compiler workload: parse, type-check, emit
bytecode.

## What it runs

One process: the `ocamlc` from the switch being tested (`~/.opam/running-ng-<runtime>/bin/ocamlc`),
compiling a single big generated file.

The input is built by `ocamlc-self-compile.build.sh`. It takes the 20 classic
OCaml-testsuite benchmark files that ship with js_of_ocaml
(`duniverse/js_of_ocaml/benchmarks/sources/ml/`: boyer, nucleic, raytrace, kb, fft,
fannkuch_redux, almabench, bdd, and so on), wraps each one in its own module, and
replicates the whole set 30 times. The result is `inputs/compile_workload.ml`, around
400k lines (roughly 10 MB). The replica count is tunable via the
`OCAMLC_SELF_COMPILE_REPLICAS` env var (default 30), and the file is regenerated only
when the sources or the replica count change.

The actual command run is effectively:

```
ocamlc -c inputs/compile_workload.ml -o <scratch>/out.cmo
```

The whole thing is one compilation unit, so it produces exactly one `.cmi` and one
`.cmo`, written into a per-run scratch directory that gets cleaned up afterward.

Bytecode compilation (`ocamlc`) is used on purpose rather than native (`ocamlopt`).
With `ocamlopt`, flambda-enabled variants run extra optimisation passes, so wall-time
differences between variants would mix "runtime got faster" with "this variant does
more compiler work". With `ocamlc` the same passes run everywhere, so cross-variant
deltas reflect runtime performance only.

## What it stresses

This is a minor-GC-heavy, allocation-heavy workload with a few specific extras:

- Lots of short-lived AST allocation (`Parsetree` nodes, `Location.loc` wrappers)
  during parsing and typing.
- `Hashtbl` at real scale: the typer's type hash-consing table (`TypeHash` in
  `typing/btype.ml`), plus environment and scope lookups. Note this uses `Hashtbl`,
  not `Ephemeron`. An earlier claim that it exercised ephemerons was checked and is
  wrong (nothing under `typing/`, `bytecomp/`, `driver/`, `utils/` uses `Ephemeron`
  in 5.4.1 or trunk).
- `Marshal`: writing the `.cmi` (`file_formats/cmi_format.ml`) and `.cmo`
  (`bytecomp/emitcode.ml`) is a bulk serialisation at the end of the compilation.
- `Bigarray.Array1`: the bytecode emit buffer is a byte `Bigarray`, grown with
  `blit`/`sub`. Small, but it sits in the hot bytecode-emission loop.

## Why there is no size ladder — and the uucp companion

Compilation is ~linear in program size, so scaling REPLICAS is **shape-invariant**:
more replicas give proportionally more of an identical GC pattern (`promo_frac` pinned
~0.11, major-GC count pinned ~13, everything else linear). It is *not* a DaCapo-style
Knob A — bigger just means bigger, not a new regime. And real code can't rescue this:
no self-contained OCaml program is large enough to reach the minute-scale bands (the
biggest vendored codebase, merlin, is ~15s of ocamlc and isn't standalone-compilable
anyway). So for a compiler, the useful axis is workload **character**, not size.

Hence two real, self-contained companion workloads of opposite character:

| | this bench (`ocamlc_self_compile`) | `ocamlc_compile_uucp` |
|---|---|---|
| input | JSOO numeric programs × REPLICAS | the real uucp Unicode library |
| character | compute / allocation | data / constant tables |
| heap | large, **monotonic** (~4 GB at R=130) | small, **collected** (~78 MB) |
| major GC | barely runs (~13) | **active** (~154 cycles) |
| gc% | ~40% | ~17% |
| stresses | minor-GC fast path, holding a big live set, Marshal | major-GC cadence, promotion, constant/codegen emission |

They exercise the collector in nearly opposite ways — see
[ocamlc-compile-uucp.md](ocamlc-compile-uucp.md).

**Rungs (5.5.0, Ryzen 9950X):** default = `ocamlc_self_compile` at REPLICAS=130
(~15s / 17s under olly); small = `ocamlc_compile_uucp` (~2s). The build-script default
stays REPLICAS=30 (~5s, legacy) for continuity with older results; activate the ~15s
default with `OCAMLC_SELF_COMPILE_REPLICAS=130`.

## Reading the results

At REPLICAS=30 on 5.4.1, expect wall ~8.6s, GC overhead ~33%, ~1 GB RSS, ~4400 minor /
16 major collections, ~12% promotion. On the 5.5.0 release (Ryzen) R=30 is ~3.4s; the
R=130 default is ~15s with ~4.2 GB RSS. The spread across runtime variants is small
because the workload is identical everywhere. Note: `max_rss_kb` from olly is accurate
here (unlike allocation-churn benches) — ocamlc does few collections, so the
runtime_events ring is barely resident (~4-18 MB); `max_rss_kb_excl_ring` confirms it.

If this benchmark moves, the usual suspects are the minor-allocator fast path (if
other allocation-heavy benchmarks move too), or something Marshal-specific if it moves
here but not on the AST-shaped benchmarks like `liq_parse_typecheck`.

## Notes

This benchmark builds nothing through dune. The only build step is generating the
input file and staging the compiler.

The build script hardlinks (or copies) the real `ocamlc.opt` to a uniquely-named
binary. running-ng's process filter would otherwise reject anything named `ocamlc`,
since that name is on its build-tools denylist, and runtime-events attach would fail.
The renamed binary sidesteps that.

It also pins `OCAMLLIB` in the wrapper. Some builds (for example 5.5-beta d8bb46c)
resolve the stdlib relative to `argv[0]`, so running the relocated binary from outside
the switch's `bin/` would otherwise fail with "Unbound module Stdlib". Setting
`OCAMLLIB` explicitly is correct on all the builds tested.
