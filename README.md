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
2. **Run setup script** -- `scripts/setup-monorepo.sh` populates `duniverse/`
   and `vendor/` (gitignored), applies all required patches, and runs a test
   build.  One-time step, takes ~10 minutes.
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
    ahrefs-devkit/            # ahrefs-devkit.build.sh + benchmark .ml files
  scripts/
    setup-monorepo.sh         # full setup from scratch (re-vendor + re-patch)
    vendor-cpdf.sh            # manual vendor for cpdf/camlpdf (non-dune)
    vendor-coq.sh             # manual vendor for zarith (non-dune)
    vendor-devkit-deps.sh     # manual vendor for libevent/ocurl (non-dune)
  dune-overlays/
    camlpdf/                  # hand-written dune files (upstream uses Makefile)
    cpdf-source/              # hand-written dune files (upstream uses Makefile)
    zarith/                   # hand-written dune files (upstream uses configure)
    libevent/                 # hand-written dune files (upstream uses configure)
    ocurl/                    # hand-written dune files (upstream uses configure)
  duniverse/                  # (gitignored) vendored sources from opam-monorepo
    menhir/                   # menhir parser generator
    rocq/                     # Rocq proof assistant (formerly Coq)
    alt-ergo/                 # alt-ergo SMT solver
    devkit/                   # ahrefs-devkit library
    ppxlib/ ppx_deriving/     # PPX ecosystem (alt-ergo deps)
    dolmen/ ocplib-simplex/   # alt-ergo deps
    lwt/                      # lwt async library
    lib-findlib/              # findlib library (rocq dep)
    ...                       # ~50 packages total
  vendor/                     # (gitignored) manually vendored non-dune packages
    camlpdf/                  # camlpdf + dune overlay
    cpdf-source/              # cpdf + dune overlay
    zarith/                   # zarith + dune overlay
    libevent/                 # libevent OCaml bindings + dune overlay
```

## Quick start

### System dependencies

Install these before building:

```bash
sudo apt install libgmp-dev libevent-dev libcurl4-openssl-dev libpcre3-dev zlib1g-dev
```

### First-time setup

```bash
cd ~/macro-benches
bash scripts/setup-monorepo.sh
```

This populates `duniverse/` and `vendor/`, applies all patches, generates
rocq's config/dunestrap files, and runs a test build (~10 minutes).

### Running benchmarks via running-ng

```bash
cd ~/running-ng
RUNNING_MACRO_BENCH_DIR=~/macro-benches \
CONFIG_FILE=src/running/config/macrobenchmarks_monorepo.yml \
  bash run_ocaml_bench_gc_sweep.sh
```

The config defines three runtimes (OCaml 5.4.1, trunk, OxCaml trunk).
running-ng builds each compiler, then calls the build scripts which
run `dune build` in the monorepo with that compiler on PATH.

### Manual test build

To verify the build works with the tools switch compiler:

```bash
cd ~/macro-benches
PATH="$HOME/.opam/running-ng-tools/bin:$PATH" dune build \
  duniverse/menhir/src/stage2/main.exe \
  vendor/cpdf-source/cpdfcommandrun.exe \
  duniverse/alt-ergo/src/bin/text/Main_text.exe \
  duniverse/rocq/topbin/coqc_bin.exe \
  benchmarks/ahrefs-devkit/htmlStream_bench.exe \
  --profile release
```

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
| ahrefs-devkit | latest | `benchmarks/ahrefs-devkit/*.exe` | Working |

## Rebuilding from scratch

If you need to re-vendor everything (e.g. after updating the lock file):

```bash
rm -rf duniverse/ vendor/
bash scripts/setup-monorepo.sh
```

## Vendored source patches

These patches are applied automatically by `scripts/setup-monorepo.sh`.
They are documented here for reference.

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

5. **lwt 5.6 support** -- replace `duniverse/lwt/` with the latest from git.
   The locked version (6.1.0) has C stubs incompatible with OCaml 5.6's
   renamed `socketaddr.h` macros; 6.1.1+ fixes this.

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

# 2. Rebuild from scratch
rm -rf duniverse/ vendor/
bash scripts/setup-monorepo.sh

# 3. Commit the updated sources
git add duniverse/ vendor/
git commit -m "Update vendored dependencies"
```

## Notes

- **OCaml >= 5.4 required** -- the vendored `ocaml-compiler-libs` uses the
  `Compunit` constructor introduced in OCaml 5.2.
- **System deps** -- `libgmp-dev` (zarith), `libevent-dev` (devkit),
  `libcurl4-openssl-dev` (devkit), `libpcre3-dev` (devkit),
  `zlib1g-dev` (camlzip).
- **Rocq dunestrap** -- `scripts/setup-monorepo.sh` generates the
  dunestrap dune files (`theories/Corelib/dune`, `theories/Ltac2/dune`)
  and config fallback files (`config/coq_config.ml`, etc.).  Generation
  needs `ocamlfind` and `zarith` installed in the tools switch.
- **`OCAMLPATH`** -- rocq's build tools use findlib at runtime.  The build
  script sets `OCAMLPATH` to include the switch's lib directories.
