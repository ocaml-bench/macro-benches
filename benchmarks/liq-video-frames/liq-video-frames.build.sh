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

# The wrappers forward all args to the exe: argv.1 = frame count (repetition),
# argv.2/argv.3 = frame WIDTH/HEIGHT (input size — a bigger frame scales the
# per-frame off-heap Bigarray, so the custom-block pacer forces more major
# cycles; the frozen repro leaves W/H unset = 1280x720). An output whose name
# contains "pool" gets the AVFrame-style refcounted-pool wrapper (LIQ_POOL=1,
# LIQ_TOUCH=full — toots' ocaml#14533 free-lunch path); otherwise the base
# mm-style fresh-malloc wrapper.
emit_wrapper () {  # $1 = output path
  if [[ "$1" == *pool* ]]; then
    cat > "$1" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export LIQ_POOL=1
export LIQ_TOUCH=full
exec "${REAL_EXE}" "\$@"
WRAPPER
  else
    cat > "$1" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "${REAL_EXE}" "\$@"
WRAPPER
  fi
  chmod +x "$1"
}

mkdir -p "$(dirname "${OUT}")"
emit_wrapper "${OUT}"

# Back-compat: always emit the canonical liq_video_frames_pool-<runtime> too,
# so a base-name build still leaves the pool variant in place.
POOL_OUT="${BENCH_DIR}/liq_video_frames_pool-${RUNTIME_TAG}"
[ "${OUT}" = "${POOL_OUT}" ] || emit_wrapper "${POOL_OUT}"

echo "liq-video-frames built: ${OUT}"
