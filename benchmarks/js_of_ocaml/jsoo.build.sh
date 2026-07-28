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
# Under running-ng the runtime under test lives in an opam switch named
# running-ng-${RUNTIME_TAG}. Outside running-ng (CI, a hand-driven build) there
# is no such switch, so derive the prefix from the ocamlc on PATH — the same
# compiler this script's dune build is using.
if [[ -n "${RUNNING_OCAML_SWITCH_PREFIX:-}" ]]; then
  RUNTIME_PREFIX="${RUNNING_OCAML_SWITCH_PREFIX}"
elif [[ -d "${HOME}/.opam/running-ng-${RUNTIME_TAG}" ]]; then
  RUNTIME_PREFIX="${HOME}/.opam/running-ng-${RUNTIME_TAG}"
else
  _ocamlc="$(command -v ocamlc || true)"
  [[ -n "${_ocamlc}" ]] && RUNTIME_PREFIX="$(cd "$(dirname "${_ocamlc}")/.." && pwd)"
fi
WORKLOAD="${RUNTIME_PREFIX:-/nonexistent}/bin/ocamlc.byte"
RUNTIME_LIB="${RUNTIME_PREFIX:-/nonexistent}/lib"

if [[ ! -f "${WORKLOAD}" ]]; then
  echo "ERROR: workload not found at ${WORKLOAD}" >&2
  echo "  (expected ocamlc.byte in the runtime's switch: tried" >&2
  echo "   \$RUNNING_OCAML_SWITCH_PREFIX, ~/.opam/running-ng-${RUNTIME_TAG}," >&2
  echo "   then the prefix of the ocamlc on PATH)" >&2
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

# --- Knob-A ladder workloads -------------------------------------------------
# Knob A for jsoo is the SIZE of the input bytecode.  jsoo is a whole-program
# compiler (it holds the entire program IR in memory), so RSS/live-heap grow
# with the input — a genuine footprint ladder, unlike the per-module compiler
# benches.  But jsoo's cost is driven by program STRUCTURE, not raw bytes: a
# synthetic file of thousands of tiny top-level closures is pathological (a
# 1 MB such file took 88 s).  So we build the rung inputs from REAL code: the
# 20 JSOO classic benchmark sources (boyer/nucleic/fft/...) wrapped in unique
# modules and replicated R times (the same generator ocamlc_self_compile uses),
# then compiled to a bytecode executable with THIS runtime's ocamlc so the
# magic matches (exactly as the legacy ocamlc.byte workload is per-runtime).
# Sizes (5.5.0 / Ryzen 9950X): small 30 reps ~5 MB ~5s / 0.5GB, default 80 reps
# ~13 MB ~16s / 1.7GB, large 200 reps ~34 MB ~50s / 7.8GB.  (huge deferred.)
# The .ml is runtime-independent; the .byte is per-runtime.  Both gitignored.
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

# Wrapper: each invocation compiles to a scratch dir which the trap
# cleans up — no source-tree pollution. OCAMLPATH + OCAMLFIND_CONF
# point at the runtime's libraries via absolute paths.  The first arg
# selects the workload: small/default/large -> the generated ladder
# bytecode; anything else (incl. empty) -> the legacy ocamlc.byte.
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
