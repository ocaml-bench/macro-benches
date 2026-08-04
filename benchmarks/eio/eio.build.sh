#!/usr/bin/env bash
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/eio-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building eio_bench (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

# Two benchmarks share this build, selected by output name:
#   * eio_conc_* — the input-size concurrency ladder (eio_conc_bench.exe). input size =
#     number of independent producer/consumer fiber pairs (argv.1), each on its
#     own bounded stream, so the working set (live fibers + buffered data) grows
#     ~linearly. The frozen eio_fiber_stream is a throughput bench with a tiny,
#     constant live set; this scales concurrency instead. The rung differs only
#     in its macro_base arg (n_pairs).
#   * eio_fiber_stream (default) — the frozen throughput benchmark, unchanged.
case "$(basename "${OUT}")" in
  *eio_conc_*) EXE="eio_conc_bench" ;;
  *)           EXE="eio_bench" ;;
esac

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  "benchmarks/eio/${EXE}.exe"

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/benchmarks/eio/${EXE}.exe" "${OUT}"
chmod +x "${OUT}"

echo "${EXE} built: ${OUT}"
