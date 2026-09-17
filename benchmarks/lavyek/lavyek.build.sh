#!/usr/bin/env bash
set -euo pipefail

# running-ng invokes this script DIRECTLY at run time, so it does NOT inherit
# the environment setup-monorepo.sh builds up. Source the portability library
# for its LOCALBASE exports: on FreeBSD, pkg puts headers in
# /usr/local/include, which the base clang does not search, so a vendored C
# stub that includes one fails with "'event.h' file not found" even though the
# package is installed. FreeBSD-gated and idempotent, so this is a no-op on
# Linux. scripts/tests/test-build-scripts-portable.sh enforces this line.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/lavyek-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building lavyek_bench (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  benchmarks/lavyek/lavyek_bench.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/benchmarks/lavyek/lavyek_bench.exe" "${OUT}"
chmod +x "${OUT}"

echo "lavyek_bench built: ${OUT}"
