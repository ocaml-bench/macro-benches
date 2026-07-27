# infer benchmark — maintainer runbook

Operational steps to bring the infer benchmark up on the Linux tools-switch and register it.
For *what it runs and why*, see [docs/benchmarks/infer.md](../../docs/benchmarks/infer.md).

Everything up to "Cross-runtime validation" has been validated piecewise on macOS/arm64; the
hermetic dune build (`OCAMLPATH`=prefix + in-tree `duniverse/`) and the cross-runtime run have
**not** yet been exercised end to end and need the populated `duniverse/` that only the Linux
lock produces. Treat this list as the finish-line checklist.

## Moving parts

| File | Role |
|------|------|
| `scripts/vendor-infer.sh` | clone java-only Infer (`ngorogiannis/infer @ remove-frontends`, pinned SHA) into `vendor/infer`, lay down the `dune-overlays/infer/` dune files |
| `scripts/vendor-javalib-sawja.sh` | build extlib+camlzip+javalib+sawja into a per-runtime prefix (non-dune deps; apron model) |
| `scripts/vendor-infer-corpus.sh` | fetch 4 pinned Maven Central jars + merge → `vendor/.infer-corpus/corpus.jar` |
| `benchmarks/infer/roots.idx` | committed class subset selecting the workload size |
| `benchmarks/infer/infer.build.sh` | the running-ng build hook (prefix → dune build → capture → wrapper) |

`macro-bench-infer` in `dune-project` / `macro-bench-infer.opam(.template)` declares Infer's OCaml
deps for the lock. `javalib`/`sawja` are deliberately **not** declared there — they come from the
prefix (see Phase-2 commit message / docs).

## Prerequisites

- Tools switch with `opam-monorepo` (the suite's `running-ng-tools`).
- System packages: the suite's usual set plus `libsqlite3-dev`, `zlib1g-dev` (Infer links
  sqlite3 + zlib), a JDK is **not** required (capture is JVM-free), `unzip`, `zip`, `curl`.
- `cppo` in **each runtime switch** you build under: `vendor-javalib-sawja.sh` builds extlib
  1.8.0, whose dune build preprocesses with cppo (`opam install --switch <runtime> cppo`).
  The prefix build is otherwise opam-free.  `vendor-javalib-sawja.sh` preflight-checks this.

## One-time setup

```sh
# 1. Regenerate the lock with Infer's deps (Linux tools-switch only — does not
#    reproduce on macOS: a pristine tree already fails on devkit's libevent pin).
OPAMSWITCH=running-ng-tools opam monorepo lock
make clean-all && make setup            # populates duniverse/ + runs vendor-*.sh

# 2. Vendor Infer source + corpus (idempotent; infer.build.sh also bootstraps these).
bash scripts/vendor-infer.sh
bash scripts/vendor-infer-corpus.sh     # ~15 MB fetch, checksum-verified

git add macro-benches.opam.locked dune-project *.opam && git commit -m "Lock infer deps"
```

If `opam monorepo lock` reports a non-dune dependency other than javalib/sawja, vet it the same
way (either a dune-universe overlay version or the prefix/opam-provided treatment).

## Build + run standalone (sanity, one runtime)

```sh
RUNNING_OCAML_RUNTIME_NAME=5.4.1 RUNNING_OCAML_OUTPUT=/tmp/infer-5.4.1 \
  bash benchmarks/infer/infer.build.sh
/tmp/infer-5.4.1                        # runs analyze --multicore -j12; time it
```

Expect a single cold `infer analyze --multicore` in the 5–25 s band. The 251 MB capture.db is
built once (per runtime) by the build hook; the wrapper re-analyses in place.

## Tuning to this farm

Absolute time is machine-relative; the committed `roots.idx` (~72 classes) is a starting point.
To retune:

```sh
CAP=vendor/.infer-capture-5.4.1        # produced by infer.build.sh
infer debug --source-files -o "$CAP" | grep '\.class$' | sort | awk 'NR % K == 1' \
  > benchmarks/infer/roots.idx
```

Pick `K` so the wrapper lands mid-band. Larger `roots.idx` = more work (full corpus ≈ 20× the
default, ~350 s at -j12 — the ceiling). Commit the regenerated `roots.idx`.

## Variants

- **Default (`--multicore`)**: shared-heap domains, single process — olly/runtime_events sees all
  GC. `INFER_JOBS` sets the domain count (default 12).
- **Fork companion**: `INFER_MULTICORE=0 bash benchmarks/infer/infer.build.sh` → parmap
  multi-process, for wall-clock/throughput. Consider registering it as a second program.

## Cross-runtime validation

Build the hook under each target runtime (5.2, 5.3, 5.4, trunk, ocaml-mmtk). Watch for:
- the hermetic build resolving Infer's deps from `duniverse/` with only the prefix on `OCAMLPATH`;
- capture completing on every runtime (same pinned sawja → same behaviour; the vetted corpus has
  no capture-aborting classes);
- `analyze --multicore` completing (multicore is newer in Infer — confirm it doesn't fault on the
  older/experimental runtimes; fall back to `INFER_MULTICORE=0` if a runtime can't do domains).

## running-ng registration

Add `infer` to the `OCamlBenchmarkSuite` config (`~/running-ng`, e.g.
`src/running/config/macrobenchmarks_monorepo.yml`) and the test-build list, pointing at
`benchmarks/infer/infer.build.sh`. Suggested ring size `re-25`; bump to `re-26` if runtime_events
overflow. The output is a wrapper script (not a copied binary), so on rebuilds delete the wrapper
output as well as `_build-<runtime>` (see the top-level CLAUDE.md gotcha).

## Gotchas

- `infer analyze` wants `--jobs N` / `-j N` (with a space). `-j12` glued is an unknown option and
  exits immediately doing nothing.
- `--keep-going` does **not** rescue an uncaught `Sawja_pack.Bir.Bad_stack` — vet corpus jars.
- Don't commit `vendor/.infer-*` (corpus, prefix, capture) — all under the git-ignored `vendor/`.
- **`oUnit` vs `ounit2` (hermetic build):** Infer's generated dune links findlib library `oUnit`
  (the legacy deprecated alias a normal opam switch provides via the transitional `ounit`
  package). The hermetic duniverse ships only the `ounit2` public name, so the overlay dune files
  (`dune-overlays/infer/infer/src/{clang,unit}/dune`, `src/dune`) were changed to link `ounit2`
  (same library, present name). This is why the build worked piecewise on a full macOS switch but
  not in the hermetic build.
- **extlib / camlzip duplicate:** javalib/sawja link `extlib` + `zip`, supplied by the per-runtime
  prefix; the duniverse *also* ships them (devkit depends on both), and dune rejects two libraries
  with the same public name. The clash is only visible while the prefix is on `OCAMLPATH` (infer's
  build), so `infer.build.sh` hides `duniverse/{ocaml-extlib,camlzip}` for the duration of its dune
  build and restores them via a trap. Caveat: don't build infer and devkit **concurrently** in the
  same tree — the hide window would break a parallel devkit build. running-ng's sequential
  `buildbms` is fine.
