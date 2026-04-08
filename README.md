# macro-benches

Monorepo build of OCaml macrobenchmarks. Alternative to the opam-based
`benches/macrobenchmarks/` approach: benchmark tool sources and their
dependencies are vendored into a single dune workspace and built with
`dune build` instead of `opam install`.

## Why a monorepo?

The opam-based macrobenchmark build has three pain points:

1. **Speed** -- opam dependency resolution and sequential package installation
   is slow, especially when creating satellite switches for isolation.
2. **OxCaml compatibility** -- opam pulls upstream packages that may be
   incompatible with OxCaml's type extensions (locality modes, unboxed types).
   Vendored sources can be patched in place.
3. **Simplicity** -- `dune build` on vendored sources requires no opam switch
   mutation, no satellite switches, and no solver.

The compiler is still built via opam switches (using `opam-compiler`).
Only the benchmark tool build changes.

## Directory Layout

```text
macro-benches/
  dune-project            # (lang dune 3.0)
  dune                    # (vendored_dirs vendor)
  dune-workspace          # default context, release profile
  sources.yml             # pinned versions + URLs for all vendored packages
  scripts/
    vendor-menhir.sh      # downloads and extracts menhir into vendor/
    vendor-<tool>.sh      # (one script per vendored benchmark)
  vendor/
    menhir/               # vendored menhir source tree (fetched by script)
    <tool>/               # (one directory per vendored tool + deps)
```

The `vendor/` directory is git-ignored. Sources are fetched on demand by
the vendor scripts based on pinned versions in `sources.yml`.

## Quick Start

```bash
# 1. Vendor the sources (one-time, or after version bumps in sources.yml)
bash scripts/vendor-menhir.sh

# 2. Build (uses whatever ocamlopt is on PATH)
dune build vendor/menhir/executable/stage2/main.exe --profile release

# 3. Test
_build/default/vendor/menhir/executable/stage2/main.exe --version
```

## Integration With running-ng

This repo is used by `running-ng` via build scripts in `benches/macrobenchmarks/`.
Each benchmark has two build scripts:

- `<tool>.build.sh` -- original opam-based build (installs via `opam install`)
- `<tool>.build-monorepo.sh` -- monorepo build (runs `dune build` here)

Both scripts follow the same contract: they receive environment variables from
`running-ng` and produce a binary at `$RUNNING_OCAML_OUTPUT`.

### Environment variables

Set by `running-ng` (same as the opam path):

| Variable | Description |
|----------|-------------|
| `RUNNING_OCAML_OUTPUT` | Path where the built binary should be placed |
| `RUNNING_OCAML_BENCH_DIR` | Benchmark directory (where input files live) |
| `RUNNING_OCAML_RUNTIME_NAME` | Runtime name from config (e.g. `ocaml-5.4.1`) |
| `RUNNING_OCAML_SWITCH` | opam switch name (compiler is on PATH) |

Set by the build script (optional override):

| Variable | Description |
|----------|-------------|
| `RUNNING_MACRO_MONOREPO_DIR` | Path to this repo. Defaults to `../macro-benches` relative to `benches/`. Set this if the repo is cloned elsewhere. |

### running-ng config

Use `macrobenchmarks_monorepo.yml`:

```bash
running runbms <log_dir> macrobenchmarks_monorepo.yml
```

This config uses `OCamlBenchmarkSuite` (not `OCamlMacroBenchmarkSuite`)
because the monorepo build doesn't install into the opam switch, so
satellite switch isolation is unnecessary.

### Build directory isolation

The monorepo build scripts use `--build-dir _build-<runtime-name>` so that
multiple compiler versions can build concurrently without sharing dune's
`_build/` cache.

## Adding a New Benchmark

### 1. Add a vendor script

Create `scripts/vendor-<tool>.sh` following the pattern in `vendor-menhir.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="..."
URL="..."
MD5="..."
# Download, verify checksum, extract to vendor/<tool>/
```

### 2. Pin the version in sources.yml

```yaml
<tool>:
  version: "<version>"
  url: "<tarball-url>"
  md5: "<checksum>"
```

### 3. Vendor and test the build

```bash
bash scripts/vendor-<tool>.sh
dune build vendor/<tool>/<path-to-executable> --profile release
```

If the tool already uses dune, this should work out of the box.
If it uses ocamlbuild or autotools, you'll need to add dune files.

### 4. Handle dependencies

If the tool has external dependencies (other opam packages):

- Vendor them into `vendor/<dep>/` with their own vendor scripts
- They'll be built automatically by dune when the tool depends on them
- For OxCaml-adapted versions, check [oxmono](https://github.com/avsm/oxmono)
  first -- it may already have patched versions

### 5. Create the build script in benches/

Create `benches/macrobenchmarks/<tool>/<tool>.build-monorepo.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/<tool>-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../../../macro-benches" && pwd)}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNNING_OCAML_RUNTIME_NAME:-default}"

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  vendor/<tool>/<path-to-executable>

cp "${BUILD_DIR}/default/vendor/<tool>/<path-to-executable>" "${OUT}"
chmod +x "${OUT}"
```

### 6. Register in macrobenchmarks_monorepo.yml

Add a suite entry in `running-ng/src/running/config/macrobenchmarks_monorepo.yml`:

```yaml
suites:
  macro-<tool>-monorepo:
    type: OCamlBenchmarkSuite
    timeout: 600
    programs:
      <benchmark-name>:
        path: "${RUNNING_BENCH_DIR}/macrobenchmarks/<tool>"
        build_script: "<tool>.build-monorepo.sh"
        args: "<arguments>"

benchmarks:
  macro-<tool>-monorepo:
    - <benchmark-name>
```

## Current Benchmarks

| Benchmark | Status | Vendor Script | Notes |
|-----------|--------|---------------|-------|
| menhir | Working | `vendor-menhir.sh` | Self-contained, no external deps |
| cpdf | Planned | -- | Needs camlpdf vendored (ocamlfind-based, needs dune port) |
| coq | Planned | -- | Needs rocq-runtime + zarith |
| alt-ergo | Planned | -- | Needs dolmen ecosystem |
| cubicle | Planned | -- | OCaml < 5.0 only, uses autotools |
| frama-c | Planned | -- | Largest dep tree, may remain opam-only |

## Relationship to oxmono

[oxmono](https://github.com/avsm/oxmono) is Anil Madhavapeddy's monorepo of
OxCaml-adapted community packages. When vendoring dependencies that need
OxCaml patches, check oxmono first -- it may already have working versions
of packages like zarith, ppxlib, fmt, cmdliner, etc.
