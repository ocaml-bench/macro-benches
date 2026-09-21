#!/usr/bin/env bash
# pplacer.build.sh: build pplacer's test suite or likelihood driver from
# vendor/pplacer (manually vendored; mcl needs the pre-built C libs in vendor/pplacer/mcl/).
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

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

# Output name selects the family: pplacer_like_* builds like_bench.exe (the
# n_sites ladder; argv.1 = column-replication factor PPLACER_LIKE_MULT, see
# dune-overlays/pplacer/like_bench.ml), anything else the OUnit suite looped
# argv.1 times in-process (PPLACER_TEST_LOOP).
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
    # Tests reference ./tests/data/ relative paths, hence the cd.
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
