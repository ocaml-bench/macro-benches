#!/usr/bin/env bash
# coq.build.sh — build coqc from the macro-benches monorepo.
#
# Rocq needs a dunestrap step (generates dune files for .vo theories).
# The generated files are cached in the source tree, so dunestrap only
# runs on the first build.
#
# Rocq's dunestrap and gen_rules tools need findlib at runtime to locate
# libraries.  We set OCAMLPATH to include both the monorepo's build
# install dir and the runtime switch's lib dir.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/coqc-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building coqc (monorepo) for runtime: ${RUNTIME_TAG}"

ROCQ_DIR="${MONOREPO_DIR}/duniverse/rocq"

# --- dunestrap: generate theories/Corelib/dune and theories/Ltac2/dune ---
# Only needed on first build; the files persist in the source tree.
if [ ! -f "${ROCQ_DIR}/theories/Corelib/dune" ] || [ ! -f "${ROCQ_DIR}/theories/Ltac2/dune" ]; then
  echo "Running dunestrap for rocq (first build)..."

  # Rocq's gen_rules tool uses findlib to locate OCaml stdlib packages.
  # Point OCAMLPATH at the runtime switch's lib dirs so it can find
  # str, dynlink, findlib, etc.
  SWITCH_LIB=""
  if command -v ocamlfind >/dev/null 2>&1; then
    SWITCH_LIB="$(ocamlfind printconf destdir 2>/dev/null || true)"
    SWITCH_LIB_OCAML="$(ocamlfind printconf stdlib 2>/dev/null || true)"
  fi

  OCAMLPATH="${SWITCH_LIB:+${SWITCH_LIB}:}${SWITCH_LIB_OCAML:+${SWITCH_LIB_OCAML}:}" \
  dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
    --profile release \
    duniverse/rocq/corelib_dune duniverse/rocq/ltac2_dune

  cp "${BUILD_DIR}/default/duniverse/rocq/corelib_dune" "${ROCQ_DIR}/theories/Corelib/dune"
  cp "${BUILD_DIR}/default/duniverse/rocq/ltac2_dune" "${ROCQ_DIR}/theories/Ltac2/dune"
  echo "dunestrap done."
fi

# --- build coqc ---
SWITCH_LIB=""
if command -v ocamlfind >/dev/null 2>&1; then
  SWITCH_LIB="$(ocamlfind printconf destdir 2>/dev/null || true)"
  SWITCH_LIB_OCAML="$(ocamlfind printconf stdlib 2>/dev/null || true)"
fi

OCAMLPATH="${SWITCH_LIB:+${SWITCH_LIB}:}${SWITCH_LIB_OCAML:+${SWITCH_LIB_OCAML}:}" \
dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/rocq/topbin/coqc_bin.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/duniverse/rocq/topbin/coqc_bin.exe" "${OUT}"
chmod +x "${OUT}"

echo "coqc built: ${OUT}"
