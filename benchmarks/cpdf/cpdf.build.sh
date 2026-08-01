#!/usr/bin/env bash
# cpdf.build.sh — build cpdf from the macro-benches monorepo.
#
# cpdf + camlpdf are manually vendored (non-dune upstream) with hand-written
# dune overlays in vendor/.
set -euo pipefail

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

# Knob-A squeeze ladder. Knob A = document working set: merge N copies of the
# input PDF (so the whole parsed object graph is resident at once — top_heap
# grows ~linearly with N) and recompress every stream (-squeeze), which is the
# CPU that lifts wall into the small/default/large time bands. The copy count N
# arrives as argv.1 (set per rung in macro_base.yml: 8/24/64), so all three rungs
# share one wrapper. Emitted for any output whose name contains "cpdf_squeeze_"
# (the rungs); the plain cpdf_* programs — including the cpdf_squeeze anchor — get
# a straight copy of the exe and select their op via args, as before.
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
