#!/usr/bin/env bash
# ocamlformat.build.sh: build ocamlformat (the benchmark binary is ocamlformat itself).
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/ocamlformat-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building ocamlformat (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

# Ladder inputs: workload.ml concatenated N times (ocamlformat only reprints
# syntax, so duplicate definitions are fine; it holds the whole AST, so RSS grows
# with N: 12x ~5s/0.6GB, 30x ~13s/1.7GB, 150x ~90s/8.8GB on 5.5.0). Gitignored.
# They must live beside .ocamlformat, else ocamlformat disables itself
# ("no project root found") and skips formatting.
for n in 12 30 150; do
  wl="${BENCH_DIR}/wl_${n}x.ml"
  if [ ! -s "${wl}" ]; then
    for _ in $(seq 1 "${n}"); do cat "${BENCH_DIR}/workload.ml"; done > "${wl}"
  fi
done

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/ocamlformat/bin/ocamlformat/main.exe

mkdir -p "$(dirname "${OUT}")"
rm -f "${OUT}"
cp "${BUILD_DIR}/default/duniverse/ocamlformat/bin/ocamlformat/main.exe" "${OUT}"
chmod +x "${OUT}"

echo "ocamlformat built: ${OUT}"
