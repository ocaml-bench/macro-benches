#!/usr/bin/env bash
# ahrefs-devkit.build.sh: build the ahrefs-devkit benchmarks. devkit is in
# duniverse/; its C-binding deps libevent + ocurl are in vendor/ with dune
# overlays. System deps: libevent-dev, libcurl4-openssl-dev.
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/devkit-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

OUT_BASE="$(basename "${OUT}")"
BM_NAME="${OUT_BASE%-${RUNTIME_TAG}}"

# The htmlstream rungs reuse htmlStream_bench (scale factor is argv.1), hence the
# shared arm. The manifest ci-check parses these arms and requires them to match
# the manifest's devkit programs exactly.
case "${BM_NAME}" in
  devkit_htmlstream|devkit_htmlstream_small|devkit_htmlstream_default|devkit_htmlstream_large)
                     EXE="htmlStream_bench" ;;
  devkit_stre)       EXE="stre_bench" ;;
  devkit_network)    EXE="network_bench" ;;
  devkit_gzip)       EXE="gzip_bench" ;;
  *)
    echo "Unknown benchmark: ${BM_NAME}" >&2
    exit 1
    ;;
esac

echo "Building ${EXE} (ahrefs-devkit monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  "benchmarks/ahrefs-devkit/${EXE}.exe"

REAL_EXE="${BUILD_DIR}/default/benchmarks/ahrefs-devkit/${EXE}.exe"

mkdir -p "$(dirname "${OUT}")"

# stre/gzip/network read Sys.argv.(1) as an in-process loop count; htmlstream is
# long enough to run bare.
case "${BM_NAME}" in
  devkit_stre|devkit_gzip|devkit_network)
    cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "${REAL_EXE}" "\${1:-1}"
WRAPPER
    chmod +x "${OUT}"
    ;;
  *)
    cp "${REAL_EXE}" "${OUT}"
    chmod +x "${OUT}"
    ;;
esac

echo "${EXE} built: ${OUT}"
