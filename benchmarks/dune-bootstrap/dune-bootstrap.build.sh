#!/usr/bin/env bash
# dune-bootstrap.build.sh — "build" step for the dune bootstrap benchmark.
#
# The dune bootstrap benchmark measures the time to compile dune itself
# from source using `ocaml boot/bootstrap.ml`.  This exercises the OCaml
# compiler on ~100K LOC of real-world code.
#
# Unlike other benchmarks, the "binary" is a wrapper script that runs the
# bootstrap from the vendored dune_ source.  The build step just creates
# this wrapper.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/dune_bootstrap-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"

echo "Preparing dune bootstrap benchmark for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

DUNE_SRC="${MONOREPO_DIR}/duniverse/dune_"

# Resolve the runtime-under-test's ocaml interpreter explicitly. The
# previous version invoked plain `ocaml` and relied on $PATH, which
# silently picked up whichever opam switch happened to be first on PATH
# (typically *not* the runtime being benchmarked) — so all cells ran
# against the same ocaml regardless of the runtime label.
OCAML_BIN="${HOME}/.opam/running-ng-${RUNTIME_TAG}/bin/ocaml"
OCAMLC_BIN="${HOME}/.opam/running-ng-${RUNTIME_TAG}/bin/ocamlc"
if [[ ! -x "${OCAML_BIN}" ]]; then
  echo "ERROR: ocaml not found at ${OCAML_BIN}" >&2
  exit 1
fi
echo "  using ocaml:  ${OCAML_BIN}"

# Stage a renamed copy of the ocaml bytecode interpreter so its
# /proc/<pid>/exe basename is `dune_bootstrap_bin-<RUNTIME_TAG>` rather
# than `ocaml` (which is in running-ng's BUILD_TOOLS list and would be
# rejected by pid_is_benchmark, leaving olly with no PID to attach to —
# the cause of the 0.0 wall_time we saw on the clean-rebuild smoketest).
# Hardlink avoids a 25 MB copy; cp falls back across filesystems.
OCAML_REAL="$(readlink -f "${OCAML_BIN}")"
STAGED_OCAML="${BENCH_DIR}/dune_bootstrap_bin-${RUNTIME_TAG}"
ln -f "${OCAML_REAL}" "${STAGED_OCAML}" 2>/dev/null \
  || cp -f "${OCAML_REAL}" "${STAGED_OCAML}"
echo "  staged ocaml: ${STAGED_OCAML}"

# Pin OCAMLLIB. Some OCaml builds (e.g. 5.5-beta d8bb46c) resolve stdlib
# relative to argv[0], so executing the staged hardlink from outside the
# switch's bin/ directory makes stdlib resolution fail. Setting
# OCAMLLIB explicitly is correct for both old and new builds.
OCAMLLIB_DIR="$(${OCAMLC_BIN} -where)"
echo "  OCAMLLIB pin: ${OCAMLLIB_DIR}"

# Create a wrapper script that runs the dune bootstrap.
# Each invocation cleans _boot/ and _build/ then bootstraps fresh.
mkdir -p "$(dirname "${OUT}")"
RUNTIME_BIN="${HOME}/.opam/running-ng-${RUNTIME_TAG}/bin"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
cd "${DUNE_SRC}"
rm -rf _boot _build
export OCAMLLIB="${OCAMLLIB_DIR}"
# boot/bootstrap.ml shells out to a bare \`ocamlc\` (Sys.command), so the
# right one must be first on PATH. running-ng's wrapper script
# (run_ocaml_bench_gc_sweep.sh) prepends a "tools switch" — typically
# whichever opam switch has dune installed first — and that ends up
# *before* the runtime under test in PATH, so without this prepend
# every cell would compile against the tools switch's ocamlc, not the
# one we're benchmarking.
export PATH="${RUNTIME_BIN}:\$PATH"
exec "${STAGED_OCAML}" boot/bootstrap.ml
WRAPPER
chmod +x "${OUT}"

echo "dune bootstrap wrapper: ${OUT}"
