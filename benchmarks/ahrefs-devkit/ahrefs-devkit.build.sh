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

REAL_EXE="${BUILD_DIR}/default/benchmarks/ahrefs-devkit/${EXE}.exe"

mkdir -p "$(dirname "${OUT}")"

# For sub-second benchmarks, an in-process iteration loop scales wall time
# inside a single OCaml process (so olly observes the full run). The .ml
# entry points read Sys.argv.(1) as the loop count; the wrapper just exec's
# the binary with the arg passed through. See ~/macro-benches/README.md
# §"Iteration counts" for the pattern.
#
# devkit_htmlstream is large enough on its own and uses the binary directly.
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
