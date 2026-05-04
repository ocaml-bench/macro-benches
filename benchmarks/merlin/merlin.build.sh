#!/usr/bin/env bash
# merlin.build.sh — build the in-process merlin-domains driver.
#
# Notes vs other benchmarks:
#   * No --profile release. The merlin-domains branch's checked-in
#     parser_raw.ml references MenhirLib.StaticVersion.require_20201216
#     while the bundled menhirLib.ml provides require_20250912. dune's
#     release profile uses the checked-in parser_raw.ml directly; the
#     dev profile lets menhir regenerate parser_raw.ml from
#     parser_raw.mly so the require call matches. We use the dev path
#     (default profile) until upstream merlin fixes the mismatch.
#   * gen_config.ml in the merlin-domains branch only enumerates OCaml
#     versions up to 5.3 in its variant type, so 5.4.1 / 5.5-beta /
#     trunk all fail to compile. The patch is applied via
#     scripts/setup-monorepo.sh; see that script for the
#     `OCaml_5_4_0 | OCaml_5_5_0 | OCaml_5_6_0` extension.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/merlin_bench-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building merlin_bench (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  benchmarks/merlin/merlin_bench.exe

REAL_EXE="${BUILD_DIR}/default/benchmarks/merlin/merlin_bench.exe"
CTXT_FILE="${MONOREPO_DIR}/duniverse/merlin/tests/test-dirs/server-tests/bench.t/ctxt.ml"

# In-process iteration loop: the OCaml binary reads Sys.argv.(1) as
# the number of iterations. Each iteration runs all 7 cram-bench
# queries against the 51 319-line ctxt.ml. The wrapper exec's the
# binary with the arg passed through and exports MERLIN_BENCH_CTXT
# so the binary doesn't need to derive the path itself.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export MERLIN_BENCH_CTXT="${CTXT_FILE}"
exec "${REAL_EXE}" "\${1:-1}"
WRAPPER
chmod +x "${OUT}"

echo "merlin_bench built: ${OUT}"
