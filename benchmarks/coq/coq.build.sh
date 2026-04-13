#!/usr/bin/env bash
# coq.build.sh — build coqc from the macro-benches monorepo.
#
# Prerequisites (one-time setup, see README):
#   - Config fallback files in duniverse/rocq/config/
#   - Dunestrap files in duniverse/rocq/theories/{Corelib,Ltac2}/dune
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/coqc-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building coqc (monorepo) for runtime: ${RUNTIME_TAG}"

# --- Sanitize environment ---
# Clear opam/OCaml env vars that would cause findlib or dune to pick up
# .cmi files from the wrong switch.  The runtime compiler is on PATH
# (set by running-ng); dune is also on PATH (from tools switch).
unset OPAM_SWITCH_PREFIX
unset OCAMLTOP_INCLUDE_PATH
unset CAML_LD_LIBRARY_PATH
unset OCAMLLIB
export OCAMLPATH=""

# --- Verify prerequisites ---
ROCQ_DIR="${MONOREPO_DIR}/duniverse/rocq"
if [ ! -f "${ROCQ_DIR}/config/coq_config.ml" ]; then
  echo "ERROR: coq_config.ml not found in ${ROCQ_DIR}/config/" >&2
  echo "Run the initial setup (see README) to generate config fallback files." >&2
  exit 1
fi
if [ ! -f "${ROCQ_DIR}/theories/Corelib/dune" ]; then
  echo "ERROR: theories/Corelib/dune not found — dunestrap not done." >&2
  echo "Run the initial setup (see README) to generate dunestrap files." >&2
  exit 1
fi

# --- Build coqc ---
dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/rocq/topbin/coqc_bin.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/duniverse/rocq/topbin/coqc_bin.exe" "${OUT}"
chmod +x "${OUT}"

echo "coqc built: ${OUT}"
