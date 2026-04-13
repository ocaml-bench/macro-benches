#!/usr/bin/env bash
# menhir.build.sh — build menhir from the macro-benches monorepo.
#
# Called by running-ng with the runtime compiler on PATH.
# The compiler (ocamlopt) comes from the runtime's opam switch; we just
# need dune to build the vendored menhir source.
#
# Environment (set by running-ng):
#   RUNNING_OCAML_OUTPUT       — path where the built binary must go
#   RUNNING_OCAML_BENCH_DIR    — this benchmark directory
#   RUNNING_OCAML_RUNTIME_NAME — runtime identifier (e.g. "ocaml-5.4.1")
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/menhir-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
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
