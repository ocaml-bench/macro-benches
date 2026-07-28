# ocamlc-compile-uucp

The companion to [ocamlc-self-compile](ocamlc-self-compile.md). Same tool — the
runtime-under-test's own `ocamlc` (bytecode) — but a deliberately different-**character**
real workload: it compiles the real [uucp](https://erratique.ch/software/uucp) Unicode
character-database library.

## Why it exists

Compiling more code is shape-invariant (see the self-compile page), so an `ocamlc`
benchmark gets coverage from workload *character*, not size. The JSOO self-compile
workload is numeric/compute code that builds a large monotonic heap the major GC barely
touches. uucp is the opposite: data/constant-heavy Unicode tables that produce a small,
actively-collected heap. Together they bracket the collector.

## What it runs

One `ocamlc` process compiling all 56 uucp `src/` modules (~99k lines) in one
invocation, in dependency order (interfaces then implementations). uucp is real,
self-contained (flat `Uucp_*` modules, stdlib-only, no ppx, no external libraries), and
compiles standalone with **zero curation** — which is rare (most substantial OCaml
libraries are dune multi-library builds with wrapping/ppx/generated modules that can't be
`ocamlc -c`'d directly).

`ocamlc-compile-uucp.build.sh` stages a copy of `duniverse/uucp/src`, computes the
compile order once (`ocamldep -sort`), and emits a wrapper that copies the sources to a
per-run scratch dir and runs the single ordered `ocamlc -c`. Warnings are disabled
(`-w -a`); nothing is written back to the source tree.

## What it stresses

- **Active major GC.** ~154 major cycles (vs ~13 for JSOO self-compile) — a real
  mark/sweep churn signal on a small working set, not a hold-a-big-heap signal.
- **Promotion** (~14%) on a small collected heap.
- **Constant / data handling in the compiler**: huge literal arrays and string tables,
  their bytecode emission and `Marshal` of the `.cmo`/`.cmi`.

## Reading the results

On 5.5.0 (Ryzen 9950X): wall ~2.0s, gc% ~17.5%, ~1 360 minor / **154 major** collections,
max RSS ~78 MB. It is short (~2s) by design — its value is the *shape*, not the clock —
but it does substantial real GC work (unlike a startup-dominated sub-second run).

If this moves but `ocamlc_self_compile` does not, suspect the **major GC** specifically
(pacing, mark/sweep, promotion) rather than the minor allocator or large-heap handling.
`max_rss_kb` from olly is accurate here (few enough events that the runtime_events ring
is barely resident); `max_rss_kb_excl_ring` confirms it.
