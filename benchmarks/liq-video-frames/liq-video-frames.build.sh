#!/usr/bin/env bash
# liq-video-frames.build.sh — synthetic GC-pacer benchmark modelling the
# liquidsoap video-frame allocation pattern (ocaml/ocaml#13123, #14533).
# Per-frame: three Bigarrays sized as mm/Image.YUV420.create for 720p.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/liq_video_frames-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
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
# number of frames to allocate. The wrappers pass the arg through and
# exec — single observable OCaml process.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "${REAL_EXE}" "\${1:-1}"
WRAPPER
chmod +x "${OUT}"

OUT_BASE="${BENCH_DIR}/liq_video_frames"

# Pool variant: AVFrame-style refcounted-pool semantics. Reproduces toots'
# ocaml#14533 free-lunch shape — under M=250, CPU drops significantly with
# no RSS growth (the shared pool buffer caps committed memory regardless
# of GC release cadence). LIQ_TOUCH=full preserves the real-pipeline
# every-pixel-write mutator cost; POOL=1 selects the refcounted-pool path.
POOL_OUT="${OUT_BASE}_pool-${RUNTIME_TAG}"
cat > "${POOL_OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export LIQ_POOL=1
export LIQ_TOUCH=full
exec "${REAL_EXE}" "\${1:-1}"
WRAPPER
chmod +x "${POOL_OUT}"

echo "liq-video-frames built: ${OUT} (plus LIQ_POOL variant wrapper)"
