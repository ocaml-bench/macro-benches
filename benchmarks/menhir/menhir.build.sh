#!/usr/bin/env bash
# menhir.build.sh — build menhir from the macro-benches monorepo.
#
# Called by running-ng with the runtime compiler on PATH.
# The compiler (ocamlopt) comes from the runtime's opam switch; we just
# need dune to build the vendored menhir source.
#
# Environment (set by running-ng):
#   RUNNING_OCAML_OUTPUT       — path where the built binary must go
#   RUNNING_OCAML_BENCH_DIR    — this benchmark directory
#   RUNNING_OCAML_RUNTIME_NAME — runtime identifier (e.g. "ocaml-5.4.1")
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/menhir-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building menhir (monorepo) for runtime: ${RUNTIME_TAG}"

# Sanitize environment to avoid cross-runtime .cmi contamination.
unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/menhir/src/stage2/main.exe

REAL_EXE="${BUILD_DIR}/default/duniverse/menhir/src/stage2/main.exe"

# Repetition wrapper: run the real menhir MENHIR_REPEAT times (default 3).
# On current hardware a single grammar run is only ~1-13s — too short to
# measure well (sql_parser was ~1s). Each grammar's automaton-construction
# footprint is identical run-to-run, so looping raises wall time into the
# old ~3/20/33 s bands WITHOUT changing the per-run RSS/live footprint that
# defines the ladder (max RSS across the sequential runs = one run's peak).
# MENHIR_REPEAT=1 restores single-run behaviour.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
n="\${MENHIR_REPEAT:-3}"
for _ in \$(seq 1 "\$n"); do
  "${REAL_EXE}" "\$@"
done
WRAPPER
chmod +x "${OUT}"

echo "menhir built (repeat-wrapper): ${OUT}"
