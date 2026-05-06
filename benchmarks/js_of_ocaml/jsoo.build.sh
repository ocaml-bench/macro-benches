#!/usr/bin/env bash
# jsoo.build.sh — build js_of_ocaml + emit a wrapper that compiles the
# runtime's ocamlc.byte to JavaScript.
#
# Workload: the OCaml bytecode compiler `ocamlc.byte` shipped in the
# runtime-under-test's switch (~3.5 MB of bytecode, runtime-specific
# by construction). jsoo translates it to JS — exercising bytecode
# parsing, the SSA / IR pipeline, optimisation passes, and JS output.
# Wall time ~8-10s per invocation across our matrix.
#
# Why ocamlc.byte and not a smaller workload:
#   - Real-world (the OCaml stdlib's compiler frontend).
#   - Naturally per-runtime: each switch ships its own bytecode-magic-
#     matched ocamlc.byte. No need to hand-build a workload.
#   - Big enough to land in the macrobench 5-60s envelope without an
#     in-process iteration loop.
#
# Vendor requirements:
#   - duniverse/js_of_ocaml on the `ocaml-5.6` branch (not the 6.2.0
#     release): supports OCaml 4.13 ≤ x < 5.7, covering our 5.4.1 /
#     5.5-beta / trunk targets.
#   - duniverse/cmdliner on tag v2.1.0 (not 1.3): jsoo's command-line
#     parser uses Cmdliner.Arg.Completion which is 2.0+.
#   See scripts/setup-monorepo.sh for how the branches are pinned.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/jsoo-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building js_of_ocaml (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/js_of_ocaml.exe

REAL_EXE="${BUILD_DIR}/default/duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/js_of_ocaml.exe"
RUNTIME_PREFIX="${HOME}/.opam/running-ng-${RUNTIME_TAG}"
WORKLOAD="${RUNTIME_PREFIX}/bin/ocamlc.byte"
RUNTIME_LIB="${RUNTIME_PREFIX}/lib"

if [[ ! -f "${WORKLOAD}" ]]; then
  echo "ERROR: workload not found at ${WORKLOAD}" >&2
  echo "  (expected ocamlc.byte in the runtime's switch)" >&2
  exit 1
fi
echo "  workload: ${WORKLOAD} ($(wc -c <"${WORKLOAD}") bytes)"

# The opam-installed findlib.conf uses *relative* paths (`destdir="."`,
# `path="./ocaml:."`) which findlib resolves against CWD, not against
# the conf file's directory. Running jsoo from a CWD other than
# $RUNTIME_LIB therefore fails with `No_such_package(stdlib)`. Writing
# a sibling conf with absolute paths lets us point OCAMLFIND_CONF at
# something that's CWD-independent.
FINDLIB_CONF_ABS="${BENCH_DIR}/findlib-${RUNTIME_TAG}.conf"
{
  echo "destdir=\"${RUNTIME_LIB}\""
  echo "path=\"${RUNTIME_LIB}/ocaml:${RUNTIME_LIB}\""
  echo 'ocamlc="ocamlc.opt"'
  echo 'ocamlopt="ocamlopt.opt"'
  echo 'ocamldep="ocamldep.opt"'
  echo 'ocamldoc="ocamldoc.opt"'
} > "${FINDLIB_CONF_ABS}"
echo "  findlib conf:  ${FINDLIB_CONF_ABS}"

# Wrapper: each invocation compiles to a scratch dir which the trap
# cleans up — no source-tree pollution. OCAMLPATH + OCAMLFIND_CONF
# point at the runtime's libraries via absolute paths.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
WORK_TMPDIR="\$(mktemp -d -t jsoo_bench.XXXXXX)"
trap 'rm -rf "\$WORK_TMPDIR"' EXIT
export OCAMLPATH="${RUNTIME_LIB}"
export OCAMLFIND_CONF="${FINDLIB_CONF_ABS}"
exec "${REAL_EXE}" "${WORKLOAD}" -o "\$WORK_TMPDIR/out.js"
WRAPPER
chmod +x "${OUT}"

echo "js_of_ocaml built: ${OUT}"
