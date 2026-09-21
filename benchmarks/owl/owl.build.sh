#!/usr/bin/env bash
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"
BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/owl-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
echo "Building owl (monorepo) for runtime: ${RUNTIME_TAG}"
unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""
dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" --profile release benchmarks/owl/owl_gc.exe
REAL_EXE="${BUILD_DIR}/default/benchmarks/owl/owl_gc.exe"
# argv.1 = in-process loop count; argv.2 = matrix dimension -> OWL_MATRIX_DIM
# (off-heap live set is 100 * dim^2 * 8 bytes; default 100).
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export OWL_MATRIX_DIM="\${2:-\${OWL_MATRIX_DIM:-100}}"
exec "${REAL_EXE}" "\${1:-1}"
WRAPPER
chmod +x "${OUT}"
echo "owl built: ${OUT}"
