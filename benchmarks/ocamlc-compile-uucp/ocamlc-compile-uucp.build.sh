#!/usr/bin/env bash
# ocamlc-compile-uucp.build.sh — compile the real uucp (Unicode character
# database) library with the runtime-under-test's own `ocamlc` (bytecode).
#
# Companion to ocamlc-self-compile (which compiles the JSOO numeric programs).
# The two are deliberately different-CHARACTER real compile workloads:
#
#   ocamlc-self-compile (JSOO): numeric/compute code -> large MONOTONIC heap,
#     minor-GC-dominated, major GC barely runs (holds a big live set).
#   ocamlc-compile-uucp (uucp): data/constant-heavy Unicode tables -> small
#     COLLECTED heap, ACTIVE major GC (mark/sweep churn), higher promotion.
#
# self-compile's monotonic heap is shape-invariant under scaling (a bigger heap,
# same GC pattern), so it has no size ladder. uucp is the opposite: its collected
# heap means compiling more of it scales the major-GC work (cycles + promotion) at
# a nearly flat RSS — so uucp carries the compiler's size ladder (see below).
# uucp is real, self-contained (flat Uucp_* modules, stdlib-only, no ppx), and
# compiles standalone with zero curation.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/ocamlc_compile_uucp-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"

echo "Building ocamlc-compile-uucp benchmark for runtime: ${RUNTIME_TAG}"

OCAMLC="${HOME}/.opam/running-ng-${RUNTIME_TAG}/bin/ocamlc"
OCAMLDEP="${HOME}/.opam/running-ng-${RUNTIME_TAG}/bin/ocamldep"
[ -x "${OCAMLC}" ] || { echo "ERROR: ocamlc not found at ${OCAMLC}" >&2; exit 1; }
echo "  using ocamlc: ${OCAMLC}"

SRC="${MONOREPO_DIR}/duniverse/uucp/src"
[ -d "${SRC}" ] || { echo "ERROR: uucp src not found at ${SRC}" >&2; exit 1; }

# Input-size ladder. The small/default/large rungs replicate the uucp module set
# N times (prefix-renamed Uucp -> UucpK per copy, so the N copies coexist in one
# compilation) — ocamlc then does N x the constant-table compilation. uucp's heap
# is COLLECTED (unlike self-compile's monotonic heap), so RSS stays ~flat
# (~90-120 MB) while major-GC cycles and promotion scale linearly: a cheap
# major-GC-throughput ladder. Measured 5.5.0 / Ryzen 9 9950X: N=3 ~6s/87MB/377
# major, N=8 ~17s/96MB/771 major, N=25 ~58s/120MB/1582 major. The frozen
# ocamlc_compile_uucp compiles the library once (N=1), unchanged.
case "$(basename "${OUT}")" in
  *ocamlc_compile_uucp_small*)   REPLICAS=3;  STAGE="${BENCH_DIR}/inputs/uucp_small" ;;
  *ocamlc_compile_uucp_default*) REPLICAS=8;  STAGE="${BENCH_DIR}/inputs/uucp_default" ;;
  *ocamlc_compile_uucp_large*)   REPLICAS=25; STAGE="${BENCH_DIR}/inputs/uucp_large" ;;
  *)                             REPLICAS=1;  STAGE="${BENCH_DIR}/inputs/uucp" ;;
esac

rm -rf "${STAGE}"; mkdir -p "${STAGE}"
if (( REPLICAS == 1 )); then
  # Frozen benchmark: the uucp library verbatim (original module names).
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

# Compute the single-invocation compile order (interfaces then implementations,
# both in dependency order). Done once at build time; baked into the wrapper.
ORDER="$(cd "${STAGE}" && "${OCAMLDEP}" -sort *.mli *.ml 2>/dev/null)"
MLIS="$(echo "${ORDER}" | tr ' ' '\n' | grep '\.mli$' | tr '\n' ' ')"
MLS="$(echo "${ORDER}"  | tr ' ' '\n' | grep '\.ml$'  | tr '\n' ' ')"
OCAMLLIB_DIR="$("${OCAMLC}" -where)"

# Stage a renamed copy of ocamlc.opt so olly can attach. running-ng's
# pid_is_benchmark filter rejects any /proc/<pid>/exe basename in BUILD_TOOLS
# (which includes "ocamlc"/"ocamlc.opt"), a guard against transient compiler
# subprocesses inside *other* benchmarks. Here ocamlc IS the benchmark, so we
# hardlink (or copy) it to a uniquely-named binary — mirroring
# ocamlc-self-compile. OCAMLLIB is pinned so the relocated binary still finds
# its stdlib. Per output name so the rungs don't clobber each other's binary.
OCAMLC_REAL="$(readlink -f "${OCAMLC}")"
STAGED_OCAMLC="${BENCH_DIR}/$(basename "${OUT}")_bin"
rm -f "${STAGED_OCAMLC}"
ln -f "${OCAMLC_REAL}" "${STAGED_OCAMLC}" 2>/dev/null \
  || cp -f "${OCAMLC_REAL}" "${STAGED_OCAMLC}"

# Wrapper: copy staged sources to a fresh scratch dir (clean .cmi each run),
# compile them all in ONE ocamlc process so olly sees a single compilation.
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
