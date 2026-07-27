# infer

Infer is Meta's inter-procedural static analyzer. This benchmark runs its **Java** analysis —
built java-only, no C/C++/other frontends — over a fixed slice of a real bytecode corpus, in
Infer's **multicore** (OCaml-5 domains) mode. It is the suite's first workload that exercises
`--multicore` shared-heap parallelism end to end, and the first heavy user of the
abstract-interpretation-plus-bi-abduction analysis engine (Pulse). It was added to the suite
recently.

## What it runs

One program, `infer`, running `infer analyze --multicore` over a pre-built capture database.
The workload is the **analysis** phase only: bytecode capture (parsing `.class` files into
Infer's IR) is done once at build time and excluded from measurement.

The corpus is four pinned, real-world Java libraries — guava 27.0 (collections), byte-buddy
1.12.21 (bytecode generation), lucene-core 9.12.0 (search), bcprov-jdk18on 1.78 (crypto),
11364 classes — fetched from Maven Central (checksummed) and merged into one jar by
`scripts/vendor-infer-corpus.sh`. They are diverse and, importantly, all capture cleanly under
the vendored sawja; clojure was excluded because its synthetic bytecode aborts capture with an
uncaught `Sawja_pack.Bir.Bad_stack`.

Analysing all 11364 classes takes minutes, so the measured workload is tuned down with
`--changed-files-index benchmarks/infer/roots.idx`, a committed subset of ~72 classes chosen to
land in the 5-25s band at 12-way parallelism. The full corpus is ~20x that, so the workload can
be grown for years by relaxing the index — no new corpus needed. To retune for a given machine:

```
infer debug --source-files -o <capture> | grep '\.class$' | sort \
  | awk 'NR % K == 1' > benchmarks/infer/roots.idx
```

and pick `K` so the wrapper lands in range. Parallelism is `INFER_JOBS` (default 12); the build
is oriented at machines with at least that many cores.

## Why multicore

Infer's default parallelism forks worker *processes* (parmap), each with its own heap — good
for wall-clock throughput but opaque to per-process GC instrumentation. `--multicore` instead
uses domains in a single process with a shared heap, so olly/runtime_events sees all of the
parallel GC activity. That is the mode this benchmark drives by default. (Set `INFER_MULTICORE=0`
for a fork/parmap wall-clock companion run.) Note that multicore is *slower* than fork here — the
shared-heap GC overhead is exactly the runtime behaviour worth measuring.

## The build

`infer.build.sh` has three vendored pieces. **Infer itself** is vendored manually
(`scripts/vendor-infer.sh`, pinned to the `inferbench-v1.0` tag): its upstream build is
autoconf+make that *generates* dune files, so it cannot join the opam-monorepo lock; instead a
java-only pre-generated dune overlay (`dune-overlays/infer/`) is laid down at vendor time and it
builds as an ordinary in-tree dune project. **javalib + sawja** are Infer's only non-dune deps;
like goblint's apron they are built per-runtime from pinned source into a self-contained prefix
by `scripts/vendor-javalib-sawja.sh` (only the active compiler + ocamlfind + make, no opam) and
exposed to the otherwise-hermetic dune build via `OCAMLPATH`. All of Infer's other deps (core,
atdgen, parmap, ...) come from the in-tree `duniverse/`.

The output `infer-<runtime>` is a wrapper script that runs `infer analyze --multicore` in place
on the per-runtime capture directory. Capture and analyze use the same per-runtime binary, so
the marshalled capture database (Infer serialises OCaml values into SQLite) never crosses an
OCaml-version boundary — the reason the corpus is shipped as `.class` files rather than as a
pre-built capture DB. The analysis is JVM-free: javalib parses bytecode directly, so no JDK is
needed at build or run time (only, once, offline, to produce the pinned jars).

## How to read its results

The workload stresses shared-heap multicore GC under a real, allocation-heavy analysis:
per-procedure abstract states, a large hashconsed type environment, and summary tables across
12 domains. Regressions show up as increased wall time and, under olly, as changes in
major/minor collection counts, pauses, and heap growth. Because `--changed-files-index` fixes
the exact class set analysed, the workload is byte-identical across runtimes; only the compiler
and its runtime change.
