#!/usr/bin/env bash
# coq.build.sh: build coqc from the vendored rocq. Needs duniverse/rocq/config/,
# the dunestrap files in duniverse/rocq/theories/{Corelib,Ltac2}/dune, Rocq
# installed into _rocq_prefix/ (all from setup-monorepo.sh) and a
# ~/install/default/lib/rocq-runtime symlink for .vo compilation.
# coqc execs rocqworker and loads plugins from ROCQRUNTIMELIB (default: next to
# -coqlib), so the wrapper points it at this runtime's build; only the .vo
# corelib in _rocq_prefix/ is shared.
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/coqc-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
ROCQ_PREFIX="${MONOREPO_DIR}/_rocq_prefix/rocq"

echo "Building coqc (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX
unset OCAMLTOP_INCLUDE_PATH
unset CAML_LD_LIBRARY_PATH
unset OCAMLLIB
export OCAMLPATH=""

if [ ! -f "${MONOREPO_DIR}/duniverse/rocq/config/coq_config.ml" ]; then
  echo "ERROR: coq_config.ml missing. Run setup-monorepo.sh first." >&2
  exit 1
fi

# Only the parts of rocq-runtime coqc loads: all of rocq-runtime.install also
# needs topfind, which OxCaml cannot build.
RUNTIME_LIB="${BUILD_DIR}/install/default/lib/rocq-runtime"
runtime_targets=("${RUNTIME_LIB}/META" "${RUNTIME_LIB}/rocqworker")
for p in "${ROCQ_PREFIX}"/lib/rocq-runtime/plugins/*/*.cmxs; do
  runtime_targets+=("${RUNTIME_LIB}/${p#"${ROCQ_PREFIX}/lib/rocq-runtime/"}")
done

dune_locked build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/rocq/topbin/coqc_bin.exe "${runtime_targets[@]}"

SWITCH_LIB="$(ocamlfind printconf destdir)"
SWITCH_STDLIB="$(ocamlfind printconf stdlib)"

mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
# Wrapper for coqc that sets up OCAMLPATH and -coqlib
MONOREPO_DIR="${MONOREPO_DIR}"
ROCQ_PREFIX="${ROCQ_PREFIX}"
BUILD_DIR="${BUILD_DIR}"

# rocqworker and plugins from this runtime's build, .vo files from -coqlib;
# this runtime's switch for the packages plugins require (threads)
export ROCQRUNTIMELIB="${RUNTIME_LIB}"
export OCAMLPATH="${BUILD_DIR}/install/default/lib:${SWITCH_LIB}:${SWITCH_STDLIB}"

exec "\${BUILD_DIR}/default/duniverse/rocq/topbin/coqc_bin.exe" \\
  -coqlib "\${ROCQ_PREFIX}/lib/coq" \\
  "\$@"
WRAPPER
chmod +x "${OUT}"

# Compiling an empty file loads the Prelude plugins into this build's worker.
if [ ! -x "${RUNTIME_LIB}/rocqworker" ]; then
  echo "ERROR: no rocqworker under ${RUNTIME_LIB}" >&2
  exit 1
fi
probe="$(mktemp -d)"
touch "${probe}/probe.v"
if ! "${OUT}" "${probe}/probe.v"; then
  rm -rf "${probe}"
  echo "ERROR: ${OUT} cannot compile an empty file" >&2
  exit 1
fi
rm -rf "${probe}"

echo "coqc built: ${OUT}"
