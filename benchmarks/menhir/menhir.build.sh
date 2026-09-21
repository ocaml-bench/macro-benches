#!/usr/bin/env bash
# menhir.build.sh: build the vendored menhir with the runtime compiler on PATH.
# Env (set by running-ng): RUNNING_OCAML_OUTPUT (where the binary goes),
# RUNNING_OCAML_BENCH_DIR (this directory), RUNNING_OCAML_RUNTIME_NAME (runtime id).
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/menhir-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building menhir (monorepo) for runtime: ${RUNTIME_TAG}"

# Sanitize environment to avoid cross-runtime .cmi contamination.
unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/menhir/src/stage2/main.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/duniverse/menhir/src/stage2/main.exe" "${OUT}"
chmod +x "${OUT}"

echo "menhir built: ${OUT}"
