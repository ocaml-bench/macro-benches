#!/usr/bin/env bash
# pplacer.build.sh — build pplacer test suite from vendored source.
#
# pplacer is vendored manually in vendor/pplacer/ (not via opam-monorepo).
# Its mcl dependency requires pre-built C libraries in vendor/pplacer/mcl/.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/pplacer_testsuite-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building pplacer tests (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  vendor/pplacer/tests.exe

TESTS_EXE="${BUILD_DIR}/default/vendor/pplacer/tests.exe"
PPLACER_SRC="${MONOREPO_DIR}/vendor/pplacer"

# Create a wrapper script that runs the test suite from the correct
# directory (tests reference ./tests/data/ relative paths).
#
# The first arg is the in-process iteration count, passed through to
# tests.exe via the PPLACER_TEST_LOOP env var. This keeps the benchmark
# a single observable OCaml process (good for olly) while letting us
# scale wall time by repeating the suite in-process. See macro-benches
# README §"Iteration counts" for context.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
cd "${PPLACER_SRC}"
PPLACER_TEST_LOOP="\${1:-1}" exec "${TESTS_EXE}"
WRAPPER
chmod +x "${OUT}"

echo "pplacer tests built: ${OUT}"
