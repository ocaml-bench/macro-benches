# macro-benches

Monorepo build of OCaml macrobenchmarks for cross-runtime comparison.
Benchmark tool sources and all their dependencies are vendored via
[opam-monorepo](https://github.com/tarides/opam-monorepo) into a single
dune workspace, ensuring **identical source code** across all runtimes.

The compiler is still built via opam switches (using `opam compiler`).
Only the benchmark tool build changes: `dune build` replaces `opam install`.

## How it works

1. **Lock dependencies once** -- `opam monorepo lock` resolves all transitive
   deps and writes a `.opam.locked` file (committed to git).
2. **Pull vendored sources** -- `opam monorepo pull` downloads everything into
   `duniverse/`.  No solver runs, just downloads from the lock file.
3. **Build with any compiler** -- `dune build` compiles everything from local
   source.  The runtime compiler (5.4.1, trunk, OxCaml) is on PATH; dune uses
   it automatically.  Each runtime gets its own `_build-<runtime>/` directory.

## Directory layout

```text
macro-benches/
  dune-project                # package declarations for opam-monorepo
  dune                        # (vendored_dirs duniverse vendor)
  dune-workspace              # default context, release profile
  macro-benches.opam.locked   # lock file (committed to git)
  sources.yml                 # pinned versions reference
  *.opam.template             # opam-monorepo config (opam-provided, repos)
  benchmarks/                 # build scripts + input files for running-ng
    menhir/                   # menhir.build.sh + .mly input files
    cpdf/                     # cpdf.build.sh + .pdf input files
    alt-ergo/                 # alt-ergo.build.sh + .why input files
    coq/                      # coq.build.sh + .v input files
  scripts/
    vendor-cpdf.sh            # manual vendor for cpdf/camlpdf (non-dune)
    vendor-coq.sh             # manual vendor for zarith (non-dune)
  dune-overlays/
    camlpdf/                  # hand-written dune files (upstream uses Makefile)
    cpdf-source/              # hand-written dune files (upstream uses Makefile)
    zarith/                   # hand-written dune files (upstream uses configure)
  duniverse/                  # (gitignored) vendored sources from opam-monorepo
    menhir/                   # menhir parser generator
    rocq/                     # Rocq proof assistant (formerly Coq)
    alt-ergo/                 # alt-ergo SMT solver
    ppxlib/ ppx_deriving/     # PPX ecosystem (alt-ergo deps)
    dolmen/ ocplib-simplex/   # alt-ergo deps
    lib-findlib/              # findlib library (rocq dep)
    ...                       # ~30 packages total
  vendor/                     # (gitignored) manually vendored non-dune packages
    camlpdf/                  # camlpdf + dune overlay
    cpdf-source/              # cpdf + dune overlay
    zarith/                   # zarith + dune overlay
```

## Quick start

### First-time setup

```bash
# 1. Pull vendored sources from lock file
cd ~/macro-benches
OPAMSWITCH=running-ng-tools /usr/local/bin/opam monorepo pull \
  --lockfile=macro-benches.opam.locked

# 2. Patch vendored dune_ (needs lang version downgrade for dune 3.21)
sed -i 's/lang dune 3.22/lang dune 3.21/' duniverse/dune_/dune-project
rm -rf duniverse/dune_/test

# 3. Vendor cpdf + camlpdf (non-dune, needs manual dune overlays)
bash scripts/vendor-cpdf.sh

# 4. Vendor zarith (non-dune, needs manual dune overlay + GMP)
bash scripts/vendor-coq.sh
# (only zarith from this script is needed; rocq is already in duniverse)
rm -rf vendor/rocq  # avoid duplicate with duniverse/rocq

# 5. Test build (requires OCaml >= 5.4 on PATH)
PATH="$HOME/.opam/running-ng-tools/bin:$PATH" dune build \
  duniverse/menhir/src/stage2/main.exe \
  vendor/cpdf-source/cpdfcommandrun.exe \
  duniverse/alt-ergo/src/bin/text/Main_text.exe \
  duniverse/rocq/topbin/coqc_bin.exe \
  --profile release
```

### Running benchmarks via running-ng

```bash
cd ~/running-ng
export RUNNING_MACRO_BENCH_DIR="$HOME/macro-benches"
CONFIG_FILE=src/running/config/macrobenchmarks_monorepo.yml \
  bash run_ocaml_bench_gc_sweep.sh
```

The config defines three runtimes (OCaml 5.4.1, trunk, OxCaml trunk).
running-ng builds each compiler, then calls the build scripts which
run `dune build` in the monorepo with that compiler on PATH.

## Build scripts

Each benchmark has a build script in `benchmarks/<tool>/<tool>.build.sh`.
The script receives these env vars from running-ng:

| Variable | Description |
|----------|-------------|
| `RUNNING_OCAML_OUTPUT` | Path where the built binary must go |
| `RUNNING_OCAML_BENCH_DIR` | Benchmark directory (where input files live) |
| `RUNNING_OCAML_RUNTIME_NAME` | Runtime name (e.g. `ocaml-5.4.1`) |

The script runs `dune build --root <monorepo> --build-dir _build-<runtime>`
to build with the runtime's compiler, then copies the binary to
`$RUNNING_OCAML_OUTPUT`.

## Current benchmarks

| Benchmark | Version | Binary target | Status |
|-----------|---------|---------------|--------|
| menhir | 20250912 | `duniverse/menhir/src/stage2/main.exe` | Working |
| cpdf | 2.8.1 | `vendor/cpdf-source/cpdfcommandrun.exe` | Working |
| alt-ergo | 2.6.2 | `duniverse/alt-ergo/src/bin/text/Main_text.exe` | Working |
| coqc | Rocq 9.2 | `duniverse/rocq/topbin/coqc_bin.exe` | Working |

## Vendored source patches

Two patches are needed on the vendored sources after `opam monorepo pull`:

1. **alt-ergo ppx_blob paths** -- `duniverse/alt-ergo/src/lib/util/theories.ml`:
   change `[%blob "src/preludes/..."` to `[%blob "duniverse/alt-ergo/src/preludes/..."`
   (ppx_blob resolves paths from workspace root, not package root)

2. **alt-ergo public_name** -- `duniverse/alt-ergo/src/bin/text/dune`:
   remove `(public_name alt-ergo)` and `(package alt-ergo)` from the
   `Main_text` executable stanza (vendored executables with public_name
   don't build by default)

3. **dune_ version** -- `duniverse/dune_/dune-project`: change `3.22` to `3.21`
   and remove `duniverse/dune_/test/` (uses dune 3.22 features)

4. **ppxlib 5.6 support** -- replace `duniverse/ppxlib/` with the main branch
   from https://github.com/ocaml-ppx/ppxlib (commit 37cda2c or later).
   The locked version (0.38.0) only supports up to OCaml 5.5; the main branch
   adds Ast_506 for trunk (5.6.0+dev).
   ```bash
   rm -rf duniverse/ppxlib
   git clone --depth=1 https://github.com/ocaml-ppx/ppxlib.git duniverse/ppxlib
   rm -rf duniverse/ppxlib/.git
   ```

5. **lwt 5.6 support** -- replace `duniverse/lwt/` with the latest from git.
   The locked version (6.1.0) has C stubs incompatible with OCaml 5.6's
   renamed `socketaddr.h` macros; 6.1.1+ fixes this.
   ```bash
   rm -rf duniverse/lwt
   git clone --depth=1 https://github.com/ocsigen/lwt.git duniverse/lwt
   rm -rf duniverse/lwt/.git
   ```

6. **devkit lwt 6.x compat** -- `duniverse/devkit/lwt_engines.ml`:
   add `type Lwt_engine.engine_id += Engine_id__libevent` before the class
   and `method id = Engine_id__libevent` inside it (lwt 6.x added the
   `id` virtual method to `Lwt_engine.abstract`).

7. **libevent label fix** -- `vendor/libevent/libevent.ml`:
   add `~persist` and `~signal` labels to `set`, `set_timer`, `set_signal`
   to match the `.mli` (OCaml 5.x strict label matching).

## Updating dependencies

```bash
# 1. Re-lock (uses opam solver to find new compatible versions)
OPAMSWITCH=running-ng-tools /usr/local/bin/opam monorepo lock

# 2. Re-pull (downloads new sources)
rm -rf duniverse/
OPAMSWITCH=running-ng-tools /usr/local/bin/opam monorepo pull \
  --lockfile=macro-benches.opam.locked

# 3. Re-apply patches (see above)
# 4. Test build
```

## Notes

- **OCaml >= 5.4 required** -- the vendored `ocaml-compiler-libs` uses the
  `Compunit` constructor introduced in OCaml 5.2.
- **System deps** -- `libgmp-dev` (for zarith), `zlib1g-dev` (if camlzip used).
- **Rocq dunestrap** -- coq.build.sh handles the dunestrap step automatically
  on first build.  It needs `ocamlfind` and `zarith` installed in the runtime
  switch (or a tools switch) so the gen_rules tool can locate OCaml stdlib
  packages via findlib.
- **`OCAMLPATH`** -- rocq's build tools use findlib at runtime.  The build
  script sets `OCAMLPATH` to include the switch's lib directories.
