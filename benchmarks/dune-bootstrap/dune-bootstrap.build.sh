#!/usr/bin/env bash
# dune-bootstrap.build.sh — "build" step for the dune bootstrap benchmark.
#
# The dune bootstrap benchmark measures the time to compile dune itself
# from source using `ocaml boot/bootstrap.ml`.  This exercises the OCaml
# compiler on ~100K LOC of real-world code.
#
# Unlike other benchmarks, the "binary" is a wrapper script that runs the
# bootstrap from the vendored dune_ source.  The build step just creates
# this wrapper.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/dune_bootstrap-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"

echo "Preparing dune bootstrap benchmark for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

DUNE_SRC="${MONOREPO_DIR}/duniverse/dune_"

# Create a wrapper script that runs the dune bootstrap.
# Each invocation cleans _boot/ and _build/ then bootstraps fresh.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
cd "${DUNE_SRC}"
rm -rf _boot _build
ocaml boot/bootstrap.ml
WRAPPER
chmod +x "${OUT}"

echo "dune bootstrap wrapper: ${OUT}"
