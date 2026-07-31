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

## Operational notes (maintainers)

Validated end to end on OCaml **5.4.0** and **5.5.0** (build + one `analyze --multicore`);
trunk (5.6) and `ocaml-mmtk` are not yet exercised. The pieces:

| File | Role |
|------|------|
| `scripts/vendor-infer.sh` | clone java-only Infer (`ngorogiannis/infer`, pinned in `sources.yml`) into `vendor/infer`, lay down the `dune-overlays/infer/` dune files |
| `scripts/vendor-javalib-sawja.sh` | build cppo + extlib + camlzip + javalib + sawja into a per-runtime prefix (non-dune deps; the apron model) |
| `scripts/vendor-infer-corpus.sh` | fetch 4 pinned Maven Central jars + merge → `vendor/.infer-corpus/corpus.jar` |
| `benchmarks/infer/roots.idx` | committed class subset selecting the workload size |
| `benchmarks/infer/infer.build.sh` | the running-ng build hook (prefix → dune build → capture → wrapper) |

`macro-bench-infer` in `dune-project` / `macro-bench-infer.opam(.template)` declares Infer's OCaml
deps for the lock. `javalib`/`sawja` are deliberately **not** declared there — they come from the
prefix. All of Infer's other deps (`core`, `atdgen`, `parmap`, …) come from the in-tree `duniverse/`.

**Prerequisites.** A tools switch with `opam-monorepo`; system packages `libsqlite3-dev`,
`zlib1g-dev`, `unzip`, `zip`, `curl` (Infer links sqlite3 + zlib; capture is JVM-free, so no JDK).
No per-switch `cppo` is needed — `vendor-javalib-sawja.sh` builds the pinned cppo into the prefix,
so the whole chain is opam-free.

**One-time lock (Linux tools-switch only).** Infer's deps must be in the lock:
`OPAMSWITCH=running-ng-tools opam monorepo lock` then `make clean-all && make setup`, and commit
`macro-benches.opam.locked` + `dune-project` + `*.opam`.

**Standalone sanity (one runtime):**
```sh
RUNNING_OCAML_RUNTIME_NAME=5.4.1 RUNNING_OCAML_OUTPUT=/tmp/infer-5.4.1 \
  bash benchmarks/infer/infer.build.sh
/tmp/infer-5.4.1                        # runs analyze --multicore -j12; time it
```
The 251 MB `capture.db` is built once per runtime by the hook; the wrapper re-analyses in place.

**Tuning to a farm.** Absolute time is machine-relative; the committed `roots.idx` (~72 classes)
is a starting point. Regenerate with `infer debug --source-files -o <capture> | grep '\.class$'
| sort | awk 'NR % K == 1' > benchmarks/infer/roots.idx`, picking `K` so the wrapper lands
mid-band (full corpus ≈ 20× the default, ~350 s at `-j12` — the ceiling). Commit the result.

**Variants.** Default `--multicore` (shared-heap domains, single process, `INFER_JOBS` domains);
`INFER_MULTICORE=0` gives the fork/parmap wall-clock companion — worth registering as a second
program if throughput is wanted alongside the shared-heap GC signal.

**running-ng registration.** Add `infer` to the `OCamlBenchmarkSuite` config (and its test-build
list) pointing at `benchmarks/infer/infer.build.sh`. Suggested ring size `re-25` (bump to `re-26`
on runtime_events overflow). The output is a wrapper, not a copied binary, so on a rebuild delete
the wrapper output as well as `_build-<runtime>` (see the top-level CLAUDE.md gotcha).

**Gotchas.**
- `infer analyze` wants `--jobs N` / `-j N` **with a space**; `-j12` glued is an unknown option
  and exits immediately doing nothing.
- `--keep-going` does *not* rescue an uncaught `Sawja_pack.Bir.Bad_stack` — vet corpus jars
  (clojure was dropped for exactly this).
- Don't commit `vendor/.infer-*` (corpus, prefix, capture) — all under git-ignored `vendor/`.
- The overlay links `ounit2`, not the legacy `oUnit` alias Infer's generated dune expects: the
  hermetic duniverse ships only the `ounit2` public name (see the CLAUDE.md gotchas).
- `infer.build.sh` hides `duniverse/{ocaml-extlib,camlzip}` for the duration of its dune build
  (the prefix supplies both, and dune rejects duplicate public names) and restores them via a
  trap — so don't build infer and devkit *concurrently* in the same tree (see CLAUDE.md gotchas).
