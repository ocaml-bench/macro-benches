#!/usr/bin/env bash
# pplacer.build.sh — build pplacer test suite from vendored source.
#
# pplacer is vendored manually in vendor/pplacer/ (not via opam-monorepo).
# Its mcl dependency requires pre-built C libraries in vendor/pplacer/mcl/.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/pplacer_testsuite-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building pplacer tests (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

PPLACER_SRC="${MONOREPO_DIR}/vendor/pplacer"
mkdir -p "$(dirname "${OUT}")"

# Two benchmark families share this build script, selected by output name:
#
#  * pplacer_like_* — the input-size likelihood ladder (like_bench.exe). input size =
#    n_sites (alignment length): the generalized likelihood vectors (Glv,
#    GSL-backed OFF-HEAP Bigarrays) are sized by n_sites, so a bigger alignment
#    grows the off-heap working set. like_bench scales it by replicating the
#    reference alignment's columns (PPLACER_LIKE_MULT, passed as argv.1) and does
#    a fixed 40-point ML pendant-branch scan per edge (real placement compute) so
#    wall reaches owl-like bands (~5/15/50s at 0.2/0.65/2.2GB) instead of the
#    ~1.7 s/GB of a single Felsenstein pass. This is the pplacer likelihood hot
#    path lifted from tests/pplacer/test_like.ml (minus its exact-value assert).
#  * pplacer_testsuite (default) — the frozen OUnit test suite, looped argv.1
#    times in-process (PPLACER_TEST_LOOP): a repetition confidence bench, unchanged.
case "$(basename "${OUT}")" in
  *pplacer_like_*)
    dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
      --profile release \
      vendor/pplacer/like_bench.exe
    LIKE_EXE="${BUILD_DIR}/default/vendor/pplacer/like_bench.exe"
    cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
cd "${PPLACER_SRC}"
PPLACER_LIKE_MULT="\${1:?pplacer_like rung needs a column-replication factor as argv.1}" \\
  PPLACER_LIKE_SCAN=40 exec "${LIKE_EXE}"
WRAPPER
    chmod +x "${OUT}"
    echo "pplacer like_bench built: ${OUT}"
    ;;
  *)
    dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
      --profile release \
      vendor/pplacer/tests.exe
    TESTS_EXE="${BUILD_DIR}/default/vendor/pplacer/tests.exe"
    # Wrapper runs the suite from the correct directory (tests reference
    # ./tests/data/ relative paths). argv.1 = in-process loop count via
    # PPLACER_TEST_LOOP, keeping the benchmark one observable OCaml process.
    cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
cd "${PPLACER_SRC}"
PPLACER_TEST_LOOP="\${1:-1}" exec "${TESTS_EXE}"
WRAPPER
    chmod +x "${OUT}"
    echo "pplacer tests built: ${OUT}"
    ;;
esac
