#!/usr/bin/env bash
# ocamlc-compile-uucp.build.sh: compile the uucp library with the runtime's own
# ocamlc (bytecode). Companion to ocamlc-self-compile: uucp's constant-heavy
# tables give a small collected heap with active major GC, so it carries the
# compiler size ladder (self-compile's monotonic heap does not change shape when scaled).
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/ocamlc_compile_uucp-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"

echo "Building ocamlc-compile-uucp benchmark for runtime: ${RUNTIME_TAG}"

if [[ -n "${RUNNING_OCAML_SWITCH_PREFIX:-}" ]]; then
  OCAML_BIN="${RUNNING_OCAML_SWITCH_PREFIX}/bin"
elif [[ -n "${RUNNING_OCAML_SWITCH:-}" ]] && _p="$(opam var prefix --switch="${RUNNING_OCAML_SWITCH}" 2>/dev/null)" && [[ -n "${_p}" ]]; then
  OCAML_BIN="${_p}/bin"
else
  OCAML_BIN="$(dirname "$(command -v ocamlc || echo /nonexistent/ocamlc)")"
fi
OCAMLC="${OCAML_BIN}/ocamlc"
OCAMLDEP="${OCAML_BIN}/ocamldep"
if [[ ! -x "${OCAMLC}" ]]; then
  echo "ERROR: ocamlc not found. Put it on PATH, or set RUNNING_OCAML_SWITCH_PREFIX" >&2
  echo "  (a switch prefix) or RUNNING_OCAML_SWITCH (an opam switch name)." >&2
  exit 1
fi
echo "  using ocamlc: ${OCAMLC}"

SRC="${MONOREPO_DIR}/duniverse/uucp/src"
[ -d "${SRC}" ] || { echo "ERROR: uucp src not found at ${SRC}" >&2; exit 1; }

# Ladder: replicate the module set N times (Uucp -> UucpK so the copies coexist).
# RSS stays ~flat (~90-120 MB) while major-GC cycles scale (5.5.0: N=3 ~6s,
# 8 ~17s, 25 ~58s). The frozen program compiles the library once (N=1).
case "$(basename "${OUT}")" in
  *ocamlc_compile_uucp_small*)   REPLICAS=3;  STAGE="${BENCH_DIR}/inputs/uucp_small" ;;
  *ocamlc_compile_uucp_default*) REPLICAS=8;  STAGE="${BENCH_DIR}/inputs/uucp_default" ;;
  *ocamlc_compile_uucp_large*)   REPLICAS=25; STAGE="${BENCH_DIR}/inputs/uucp_large" ;;
  *)                             REPLICAS=1;  STAGE="${BENCH_DIR}/inputs/uucp" ;;
esac

rm -rf "${STAGE}"; mkdir -p "${STAGE}"
if (( REPLICAS == 1 )); then
  cp "${SRC}"/*.ml "${SRC}"/*.mli "${STAGE}"/ 2>/dev/null
else
  for k in $(seq 1 "${REPLICAS}"); do
    for f in "${SRC}"/*.ml "${SRC}"/*.mli; do
      b="$(basename "$f")"
      sed "s/Uucp/Uucp${k}/g" "$f" > "${STAGE}/${b/#uucp/uucp${k}}"
    done
  done
fi
echo "  staged $(ls "${STAGE}"/*.ml | wc -l) modules ($(cat "${STAGE}"/*.ml | wc -l) lines, REPLICAS=${REPLICAS})"

ORDER="$(cd "${STAGE}" && "${OCAMLDEP}" -sort *.mli *.ml 2>/dev/null)"
MLIS="$(echo "${ORDER}" | tr ' ' '\n' | grep '\.mli$' | tr '\n' ' ')"
MLS="$(echo "${ORDER}"  | tr ' ' '\n' | grep '\.ml$'  | tr '\n' ' ')"
OCAMLLIB_DIR="$("${OCAMLC}" -where)"

# Stage ocamlc.opt under a unique name (per output, so rungs don't clobber each
# other): running-ng's pid_is_benchmark filter rejects BUILD_TOOLS basenames
# ("ocamlc", "ocamlc.opt"), so olly could not attach. OCAMLLIB is pinned for the
# relocated binary, as in ocamlc-self-compile.
OCAMLC_REAL="$(readlink -f "${OCAMLC}")"
STAGED_OCAMLC="${BENCH_DIR}/$(basename "${OUT}")_bin"
rm -f "${STAGED_OCAMLC}"
ln -f "${OCAMLC_REAL}" "${STAGED_OCAMLC}" 2>/dev/null \
  || cp -f "${OCAMLC_REAL}" "${STAGED_OCAMLC}"

# Wrapper: fresh scratch copy (clean .cmi), one ocamlc process so olly sees one compilation.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
WORK="\$(mktemp -d -t ocamlc_uucp.XXXXXX)"
trap 'rm -rf "\$WORK"' EXIT
cp "${STAGE}"/* "\$WORK"/
cd "\$WORK"
export OCAMLLIB="${OCAMLLIB_DIR}"
exec "${STAGED_OCAMLC}" -c -w -a ${MLIS} ${MLS}
WRAPPER
chmod +x "${OUT}"
echo "ocamlc-compile-uucp wrapper: ${OUT}"
