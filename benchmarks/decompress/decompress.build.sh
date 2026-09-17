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
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/decompress-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
# running-ng converts each MEMTRACE trace to a JSON sidecar via this tool
# (see runbms.py's write_memtrace_json_sidecar) — built from the same
# vendored memtrace copy that produced the trace, so reader/writer never
# drift out of version sync. Named to match runtime.name exactly, since
# that's what runbms.py uses to look it up.
FLAMEGRAPH_OUT="${BENCH_DIR}/memtrace_flamegraph-${RUNNING_OCAML_RUNTIME_NAME:-runtime}"

echo "Building test_decompress (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  benchmarks/decompress/test_decompress.exe \
  duniverse/memtrace/bin/flamegraph.exe

mkdir -p "$(dirname "${OUT}")"
# -f: dune build outputs are read-only, so a plain `cp` fails on rebuild
# (always_build: true) once OUT/FLAMEGRAPH_OUT already exist from a
# previous build.
cp -f "${BUILD_DIR}/default/benchmarks/decompress/test_decompress.exe" "${OUT}"
chmod +x "${OUT}"
cp -f "${BUILD_DIR}/default/duniverse/memtrace/bin/flamegraph.exe" "${FLAMEGRAPH_OUT}"
chmod +x "${FLAMEGRAPH_OUT}"

echo "test_decompress built: ${OUT}"
echo "memtrace flamegraph tool built: ${FLAMEGRAPH_OUT}"
