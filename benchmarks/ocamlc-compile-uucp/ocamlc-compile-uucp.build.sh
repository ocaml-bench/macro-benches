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
# Compilation is ~linear in program size (shape-invariant under scaling), so
# the useful axis for an ocamlc benchmark is workload *character*, not size.
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

# Stage an immutable copy of the uucp sources.
STAGE="${BENCH_DIR}/inputs/uucp"
rm -rf "${STAGE}"; mkdir -p "${STAGE}"
cp "${SRC}"/*.ml "${SRC}"/*.mli "${STAGE}"/ 2>/dev/null
echo "  staged $(ls "${STAGE}"/*.ml | wc -l) modules ($(cat "${STAGE}"/*.ml | wc -l) lines)"

# Compute the single-invocation compile order (interfaces then implementations,
# both in dependency order). Done once at build time; baked into the wrapper.
ORDER="$(cd "${STAGE}" && "${OCAMLDEP}" -sort *.mli *.ml 2>/dev/null)"
MLIS="$(echo "${ORDER}" | tr ' ' '\n' | grep '\.mli$' | tr '\n' ' ')"
MLS="$(echo "${ORDER}"  | tr ' ' '\n' | grep '\.ml$'  | tr '\n' ' ')"
OCAMLLIB_DIR="$("${OCAMLC}" -where)"

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
exec "${OCAMLC}" -c -w -a ${MLIS} ${MLS}
WRAPPER
chmod +x "${OUT}"
echo "ocamlc-compile-uucp wrapper: ${OUT}"
