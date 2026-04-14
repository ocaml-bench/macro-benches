#!/usr/bin/env bash
# jsoo.build.sh — build js_of_ocaml compiler from the macro-benches monorepo.
#
# Blocker: js_of_ocaml 6.2.0 requires OCaml < 5.5. Builds on 5.4.1 only;
# trunk (5.6) and OxCaml will fail until jsoo releases 5.6 support.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/jsoo-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building js_of_ocaml (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/js_of_ocaml.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/js_of_ocaml.exe" "${OUT}"
chmod +x "${OUT}"

echo "js_of_ocaml built: ${OUT}"
