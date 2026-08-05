#!/usr/bin/env bash
set -euo pipefail
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
# Two knobs:
#   $1 = in-process loop count (repetition; default 1). The OCaml
#        binary reads it as Sys.argv.(1) = number of full passes over the
#        matrix-pair grid. Single observable OCaml process, olly sees it all.
#   $2 = matrix dimension (input size, working-set size) -> OWL_MATRIX_DIM. Each
#        sample point is a $2 x $2 Float64 matrix, so the off-heap Bigarray
#        live set is 100 * $2^2 * 8 bytes; raising it grows RSS ~quadratically
#        (the owl footprint ladder). Default 100 = legacy value.
# See macro-benches README §"Iteration counts" for the loop pattern.
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export OWL_MATRIX_DIM="\${2:-\${OWL_MATRIX_DIM:-100}}"
exec "${REAL_EXE}" "\${1:-1}"
WRAPPER
chmod +x "${OUT}"
echo "owl built: ${OUT}"
