#!/usr/bin/env bash
# cpdf.build.sh — build cpdf from the macro-benches monorepo.
#
# cpdf + camlpdf are manually vendored (non-dune upstream) with hand-written
# dune overlays in vendor/.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/cpdf-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building cpdf (monorepo) for runtime: ${RUNTIME_TAG}"

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  vendor/cpdf-source/cpdfcommandrun.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/vendor/cpdf-source/cpdfcommandrun.exe" "${OUT}"
chmod +x "${OUT}"

echo "cpdf built: ${OUT}"
