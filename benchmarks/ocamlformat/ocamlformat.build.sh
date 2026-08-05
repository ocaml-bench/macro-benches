#!/usr/bin/env bash
# ocamlformat.build.sh — build ocamlformat from the macro-benches monorepo.
#
# Workload: format a large OCaml source file. The benchmark binary is
# the ocamlformat executable itself.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/ocamlformat-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building ocamlformat (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

# input-size ladder inputs: the axis is source SIZE (# lines). Generate the rung
# files by concatenating workload.ml (real ~3.3k-line Rocq source) N times —
# ocamlformat only parses+reprints syntax, so duplicate definitions are fine,
# and it holds the whole AST + output document in memory, so RSS/live-heap grow
# with N (a genuine footprint+throughput ladder, unlike the compiler benches).
# Generated (not vendored — big) and gitignored; regenerated here if missing.
# Done before the build so it runs even when the output binary already exists
# (a read-only copy would make the cp below fail under `set -e`).
# N -> {lines, wall, RSS} on 5.5.0/Ryzen 9950X:
#   12x  40k   ~5s   0.6GB   (small)
#   30x  100k  ~13s  1.7GB   (default)
#   150x 500k  ~90s  8.8GB   (large)
# (A huge band ~450x / ~26 GB RSS is deferred — tracked separately.)
# These files must live beside .ocamlformat, else ocamlformat disables itself
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
