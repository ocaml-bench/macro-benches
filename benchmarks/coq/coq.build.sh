#!/usr/bin/env bash
# coq.build.sh — build coqc from the macro-benches monorepo.
#
# Prerequisites:
#   - Config fallback files in duniverse/rocq/config/
#   - Dunestrap files in duniverse/rocq/theories/{Corelib,Ltac2}/dune
#   - Rocq installed into _rocq_prefix/ (done by setup-monorepo.sh)
#   - ~/install/default/lib/rocq-runtime symlink (for .vo compilation)
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/coqc-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
ROCQ_PREFIX="${MONOREPO_DIR}/_rocq_prefix/rocq"

echo "Building coqc (monorepo) for runtime: ${RUNTIME_TAG}"

# Sanitize environment
unset OPAM_SWITCH_PREFIX
unset OCAMLTOP_INCLUDE_PATH
unset CAML_LD_LIBRARY_PATH
unset OCAMLLIB
export OCAMLPATH=""

# Verify prerequisites
if [ ! -f "${MONOREPO_DIR}/duniverse/rocq/config/coq_config.ml" ]; then
  echo "ERROR: coq_config.ml missing. Run setup-monorepo.sh first." >&2
  exit 1
fi

# Build coqc binary
dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/rocq/topbin/coqc_bin.exe

# Create a wrapper script that sets up the Rocq environment
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
# Wrapper for coqc that sets up OCAMLPATH and -coqlib
MONOREPO_DIR="${MONOREPO_DIR}"
ROCQ_PREFIX="${ROCQ_PREFIX}"
BUILD_DIR="${BUILD_DIR}"

# Set OCAMLPATH so findlib can locate rocq-runtime
export OCAMLPATH="\${ROCQ_PREFIX}/lib:\${ROCQ_PREFIX}/lib/rocq-runtime"

# Add switch lib paths if ocamlfind is available
if command -v ocamlfind >/dev/null 2>&1; then
  SWITCH_LIB="\$(ocamlfind printconf destdir 2>/dev/null || true)"
  SWITCH_STDLIB="\$(ocamlfind printconf stdlib 2>/dev/null || true)"
  export OCAMLPATH="\${OCAMLPATH}:\${SWITCH_LIB}:\${SWITCH_STDLIB}"
fi

exec "\${BUILD_DIR}/default/duniverse/rocq/topbin/coqc_bin.exe" \\
  -coqlib "\${ROCQ_PREFIX}/lib/coq" \\
  "\$@"
WRAPPER
chmod +x "${OUT}"

echo "coqc built: ${OUT}"
