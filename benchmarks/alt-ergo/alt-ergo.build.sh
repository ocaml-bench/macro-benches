#!/usr/bin/env bash
# alt-ergo.build.sh — build alt-ergo from the macro-benches monorepo.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/alt-ergo-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building alt-ergo (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/alt-ergo/src/bin/text/Main_text.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/duniverse/alt-ergo/src/bin/text/Main_text.exe" "${OUT}"
chmod +x "${OUT}"

echo "alt-ergo built: ${OUT}"
