#!/usr/bin/env bash
# jsoo.build.sh: build js_of_ocaml and emit a wrapper that compiles bytecode to
# JS. Default input is the runtime's own ocamlc.byte (per-runtime, magic-matched
# by construction); wrapper argv.1 small/default/large selects a generated ladder
# input. Vendor pins (scripts/setup-monorepo.sh): js_of_ocaml on the `ocaml-5.6`
# branch (OCaml 4.13 <= x < 5.7), cmdliner v2.1.0 (Cmdliner.Arg.Completion).
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/jsoo-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building js_of_ocaml (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/js_of_ocaml.exe

REAL_EXE="${BUILD_DIR}/default/duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/js_of_ocaml.exe"
if [[ -n "${RUNNING_OCAML_SWITCH_PREFIX:-}" ]]; then
  RUNTIME_PREFIX="${RUNNING_OCAML_SWITCH_PREFIX}"
elif [[ -n "${RUNNING_OCAML_SWITCH:-}" ]] && _p="$(opam var prefix --switch="${RUNNING_OCAML_SWITCH}" 2>/dev/null)" && [[ -n "${_p}" ]]; then
  RUNTIME_PREFIX="${_p}"
else
  _ocamlc="$(command -v ocamlc || true)"
  [[ -n "${_ocamlc}" ]] && RUNTIME_PREFIX="$(cd "$(dirname "${_ocamlc}")/.." && pwd)"
fi
WORKLOAD="${RUNTIME_PREFIX:-/nonexistent}/bin/ocamlc.byte"
RUNTIME_LIB="${RUNTIME_PREFIX:-/nonexistent}/lib"

if [[ ! -f "${WORKLOAD}" ]]; then
  echo "ERROR: workload not found at ${WORKLOAD}" >&2
  echo "  (expected ocamlc.byte in the runtime's switch: tried" >&2
  echo "   \$RUNNING_OCAML_SWITCH_PREFIX, opam var prefix --switch \$RUNNING_OCAML_SWITCH," >&2
  echo "   then the prefix of the ocamlc on PATH)" >&2
  exit 1
fi
echo "  workload: ${WORKLOAD} ($(wc -c <"${WORKLOAD}") bytes)"

# The opam findlib.conf uses relative paths (destdir=".") resolved against CWD,
# so jsoo run elsewhere fails with No_such_package(stdlib); write an absolute one.
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

# Ladder inputs: jsoo is a whole-program compiler, so live heap scales with the
# input, but cost tracks program structure (a synthetic 1 MB file of tiny
# closures took 88s), so the rungs replicate real JSOO benchmark sources and
# compile them with this runtime's ocamlc so the magic matches. 5.5.0: 30 reps
# ~5s/0.5GB, 80 ~16s/1.7GB, 200 ~50s/7.8GB. Both .ml and .byte are gitignored.
JSOO_SRC="${MONOREPO_DIR}/duniverse/js_of_ocaml/benchmarks/sources/ml"
RT_OCAMLC="${RUNTIME_PREFIX}/bin/ocamlc.opt"
[[ -x "${RT_OCAMLC}" ]] || RT_OCAMLC="${RUNTIME_PREFIX}/bin/ocamlc"
for spec in "small:30" "default:80" "large:200"; do
  rung="${spec%%:*}"; reps="${spec##*:}"
  ML="${BENCH_DIR}/jsoo_wl_${rung}.ml"
  BYTE="${BENCH_DIR}/jsoo_wl_${rung}-${RUNTIME_TAG}.byte"
  if [[ ! -s "${ML}" ]] || ! head -1 "${ML}" 2>/dev/null | grep -q "REPS=${reps}"; then
    python3 - "${JSOO_SRC}" "${ML}" "${reps}" <<'PY'
import os, glob, sys
sd, dst, r = sys.argv[1], sys.argv[2], int(sys.argv[3])
files = sorted(glob.glob(f"{sd}/*.ml"))
out = [f"(* GENERATED REPS={r}; do not edit. *)"]
for rep in range(r):
    for p in files:
        b = os.path.splitext(os.path.basename(p))[0]
        c = "".join(x if x.isalnum() else "_" for x in b)
        m = (c[0].upper() + c[1:]) + f"_{rep}"
        out += [f"module {m} = struct", open(p).read(), "end"]
open(dst, "w").write("\n".join(out) + "\n")
PY
  fi
  if [[ ! -s "${BYTE}" || "${ML}" -nt "${BYTE}" ]]; then
    echo "  compiling ladder workload ${rung} (reps=${reps}) with ${RT_OCAMLC}"
    "${RT_OCAMLC}" -w -a -o "${BYTE}" "${ML}" 2>/dev/null \
      || echo "  WARN: could not compile ${rung} workload (rung will be unavailable)"
    rm -f "${BENCH_DIR}/jsoo_wl_${rung}.cmi" "${BENCH_DIR}/jsoo_wl_${rung}.cmo"
  fi
done

mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
WORK_TMPDIR="\$(mktemp -d -t jsoo_bench.XXXXXX)"
trap 'rm -rf "\$WORK_TMPDIR"' EXIT
export OCAMLPATH="${RUNTIME_LIB}"
export OCAMLFIND_CONF="${FINDLIB_CONF_ABS}"
case "\${1:-}" in
  small|default|large) WL="${BENCH_DIR}/jsoo_wl_\${1}-${RUNTIME_TAG}.byte" ;;
  *) WL="${WORKLOAD}" ;;
esac
exec "${REAL_EXE}" "\$WL" -o "\$WORK_TMPDIR/out.js"
WRAPPER
chmod +x "${OUT}"

echo "js_of_ocaml built: ${OUT}"
