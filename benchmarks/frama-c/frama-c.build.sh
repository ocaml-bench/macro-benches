#!/usr/bin/env bash
# frama-c.build.sh — build the Frama-C EVA benchmark from the monorepo.
#
# Builds a standalone executable that statically links the Frama-C kernel
# + the EVA (value/abstract-interpretation) plugin (see benchmarks/frama-c/dune),
# then emits a wrapper that runs EVA on a C workload.
#
# The wrapper sets two things the static, uninstalled build needs:
#   * -no-autoload-plugins : EVA is statically registered, so the dune-site
#       plugin loader must NOT run (there is no plugin site to discover).
#   * DUNE_DIR_LOCATIONS   : points Frama-C's dune-site "share"/"lib" sites
#       at the vendored source tree (frama-c:share:<root> resolves to
#       <root>/share, which holds machdeps/, libc/, ...).  Without this the
#       uninstalled binary crashes in System_config (List.hd of empty site).
#
# Two workloads, selected by the wrapper's first argument:
#   t       (default) : EVA on t.c (zlib, ~17.5k lines) — abstract-interp
#                       focused, ~6s.
#   sqlite            : EVA on the SQLite amalgamation (sqlite3.c, ~258k
#                       lines) via a small driver — stresses the weak/
#                       ephemeron hashconsing of a huge CIL AST + EVA state
#                       (the OCaml-5 regression of ocaml#11733), ~7s / 460MB
#                       at -eva-slevel 0; raise slevel to push wall+RSS.
# Any other arguments are passed straight through to the EVA executable.
#
# assigns:missing is downgraded from error→feedback for the sqlite run:
# the amalgamation calls spec-less libc/OS functions that would otherwise
# abort EVA; we want it to keep analysing, not prove soundness.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/frama-c-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building frama-c EVA (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  benchmarks/frama-c/frama_c_eva.exe

REAL_EXE="${BUILD_DIR}/default/benchmarks/frama-c/frama_c_eva.exe"
SHARE_ROOT="${MONOREPO_DIR}/vendor/frama-c"

mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export DUNE_DIR_LOCATIONS="frama-c:share:${SHARE_ROOT}:frama-c:libexec:${SHARE_ROOT}"
SLEVEL="\${FRAMAC_EVA_SLEVEL:-100}"
case "\${1:-t}" in
  t)
    exec "${REAL_EXE}" -no-autoload-plugins \\
      -eva -eva-no-results -eva-slevel "\$SLEVEL" "${BENCH_DIR}/t.c" ;;
  sqlite)
    exec "${REAL_EXE}" -no-autoload-plugins \\
      -eva -eva-no-results -eva-slevel "\${FRAMAC_EVA_SLEVEL:-0}" -main main \\
      -eva-warn-key assigns:missing=feedback \\
      "${BENCH_DIR}/sqlite_driver.c" "${BENCH_DIR}/sqlite3.c" ;;
  *)
    exec "${REAL_EXE}" -no-autoload-plugins "\$@" ;;
esac
WRAPPER
chmod +x "${OUT}"

echo "frama-c EVA built: ${OUT}"
