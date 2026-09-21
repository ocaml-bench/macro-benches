#!/usr/bin/env bash
# liq-video-frames.build.sh: synthetic GC-pacer benchmark modelling liquidsoap's
# video-frame allocation pattern (ocaml/ocaml#13123, #14533).
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

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

# Args pass through: argv.1 = frame count, argv.2/3 = width/height (input size;
# unset = 1280x720). An output name containing "pool" gets the refcounted-pool
# variant (LIQ_POOL=1, LIQ_TOUCH=full: the ocaml#14533 free-lunch path).
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

# Always emit the canonical pool wrapper too, so a base-name build leaves it in place.
POOL_OUT="${BENCH_DIR}/liq_video_frames_pool-${RUNTIME_TAG}"
[ "${OUT}" = "${POOL_OUT}" ] || emit_wrapper "${POOL_OUT}"

echo "liq-video-frames built: ${OUT}"
