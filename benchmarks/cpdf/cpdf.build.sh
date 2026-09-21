#!/usr/bin/env bash
# cpdf.build.sh: build cpdf. cpdf + camlpdf are manually vendored (non-dune
# upstream) with dune overlays in vendor/.
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/cpdf-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building cpdf (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  vendor/cpdf-source/cpdfcommandrun.exe

REAL_EXE="${BUILD_DIR}/default/vendor/cpdf-source/cpdfcommandrun.exe"

# Squeeze ladder: merge N copies of the PDF (whole object graph resident, so
# top_heap grows ~linearly) and recompress every stream. N is argv.1 (8/24/64
# per rung). Only cpdf_squeeze_* outputs get this wrapper; other cpdf_* programs
# (including the cpdf_squeeze anchor) get the bare exe and pick their op via args.
emit_squeeze_ladder () {  # $1 = output path
  cat > "$1" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
N="\${1:?cpdf_squeeze rung needs a copy count as argv.1}"
PDF="${BENCH_DIR}/PDFReference16.pdf_toobig"
args=(); for _ in \$(seq 1 "\$N"); do args+=("\$PDF"); done
exec "${REAL_EXE}" -squeeze "\${args[@]}" -o /dev/null
WRAPPER
  chmod +x "$1"
}

mkdir -p "$(dirname "${OUT}")"
case "$(basename "${OUT}")" in
  *cpdf_squeeze_*)
    emit_squeeze_ladder "${OUT}"
    ;;
  *)
    cp "${REAL_EXE}" "${OUT}"
    chmod +x "${OUT}"
    ;;
esac

echo "cpdf built: ${OUT}"
