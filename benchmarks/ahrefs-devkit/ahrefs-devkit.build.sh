#!/usr/bin/env bash
# ahrefs-devkit.build.sh — build ahrefs-devkit benchmarks from the monorepo.
#
# devkit and its C-binding deps (libevent, ocurl) are vendored:
#   - devkit itself in duniverse/ (via opam-monorepo)
#   - libevent + ocurl in vendor/ (with hand-written dune overlays)
# System deps: libevent-dev, libcurl4-openssl-dev
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/devkit-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

OUT_BASE="$(basename "${OUT}")"
BM_NAME="${OUT_BASE%-${RUNTIME_TAG}}"

case "${BM_NAME}" in
  devkit_htmlstream) EXE="htmlStream_bench" ;;
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

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/benchmarks/ahrefs-devkit/${EXE}.exe" "${OUT}"
chmod +x "${OUT}"

echo "${EXE} built: ${OUT}"
