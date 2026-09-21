#!/usr/bin/env bash
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/decompress-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
# running-ng converts MEMTRACE traces to JSON with this tool (runbms.py's
# write_memtrace_json_sidecar); building it from the same vendored memtrace
# keeps reader and writer in sync. The name must match runtime.name exactly.
FLAMEGRAPH_OUT="${BENCH_DIR}/memtrace_flamegraph-${RUNNING_OCAML_RUNTIME_NAME:-runtime}"

echo "Building test_decompress (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  benchmarks/decompress/test_decompress.exe \
  duniverse/memtrace/bin/flamegraph.exe

mkdir -p "$(dirname "${OUT}")"
# -f: dune outputs are read-only, so a plain cp fails on rebuild (always_build: true).
cp -f "${BUILD_DIR}/default/benchmarks/decompress/test_decompress.exe" "${OUT}"
chmod +x "${OUT}"
cp -f "${BUILD_DIR}/default/duniverse/memtrace/bin/flamegraph.exe" "${FLAMEGRAPH_OUT}"
chmod +x "${FLAMEGRAPH_OUT}"

echo "test_decompress built: ${OUT}"
echo "memtrace flamegraph tool built: ${FLAMEGRAPH_OUT}"
