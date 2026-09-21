#!/usr/bin/env bash
# merlin.build.sh: build the in-process merlin-domains driver.
# No --profile release: the branch's checked-in parser_raw.ml requires
# MenhirLib.StaticVersion.require_20201216 but the bundled menhirLib provides
# require_20250912; the dev profile regenerates parser_raw.ml from the .mly.
# gen_config.ml only knows OCaml versions up to 5.3; scripts/setup-monorepo.sh patches it.
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/merlin_bench-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building merlin_bench (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  benchmarks/merlin/merlin_bench.exe

REAL_EXE="${BUILD_DIR}/default/benchmarks/merlin/merlin_bench.exe"
CTXT_FILE="${MONOREPO_DIR}/duniverse/merlin/tests/test-dirs/server-tests/bench.t/ctxt.ml"

# argv.1 = in-process iteration count; MERLIN_BENCH_CTXT tells the binary where ctxt.ml is.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export MERLIN_BENCH_CTXT="${CTXT_FILE}"
exec "${REAL_EXE}" "\${1:-1}"
WRAPPER
chmod +x "${OUT}"

echo "merlin_bench built: ${OUT}"
