#!/usr/bin/env bash
# liq-video-frames.build.sh — synthetic memory-footprint benchmark
# probing the GC pacer's response to a deadweight + streaming-allocation
# workload (ocaml/ocaml#13123).
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/liq_video_frames-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building liq-video-frames for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  benchmarks/liq-video-frames/liq_video_frames.exe

REAL_EXE="${BUILD_DIR}/default/benchmarks/liq-video-frames/liq_video_frames.exe"

# In-process iteration loop: the OCaml binary reads Sys.argv.(1) as the
# number of frames to allocate. The wrapper just passes the arg through
# and exec's — single observable OCaml process, olly sees the whole
# run. See README §"Iteration counts" for the pattern.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "${REAL_EXE}" "\${1:-1}"
WRAPPER
chmod +x "${OUT}"

echo "liq-video-frames built: ${OUT}"
