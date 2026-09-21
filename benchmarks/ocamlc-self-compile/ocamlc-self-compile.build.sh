#!/usr/bin/env bash
# ocamlc-self-compile.build.sh: run the runtime's own ocamlc (bytecode) on a
# generated input; ocamlc itself exercises ephemerons, Hashtbl and Marshal.
# Bytecode rather than ocamlopt so flambda variants do the same compiler work
# and deltas reflect runtime performance only. Nothing is built with dune: this
# only generates the input and emits a wrapper at ${OUT}.

set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/ocamlc_self_compile-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"

echo "Building ocamlc-self-compile benchmark for runtime: ${RUNTIME_TAG}"

if [[ -n "${RUNNING_OCAML_SWITCH_PREFIX:-}" ]]; then
  OCAMLC="${RUNNING_OCAML_SWITCH_PREFIX}/bin/ocamlc"
elif [[ -n "${RUNNING_OCAML_SWITCH:-}" ]] && _p="$(opam var prefix --switch="${RUNNING_OCAML_SWITCH}" 2>/dev/null)" && [[ -n "${_p}" ]]; then
  OCAMLC="${_p}/bin/ocamlc"
else
  OCAMLC="$(command -v ocamlc || true)"
fi
if [[ -z "${OCAMLC}" || ! -x "${OCAMLC}" ]]; then
  echo "ERROR: ocamlc not found. Put it on PATH, or set RUNNING_OCAML_SWITCH_PREFIX" >&2
  echo "  (a switch prefix) or RUNNING_OCAML_SWITCH (an opam switch name)." >&2
  exit 1
fi
echo "  using ocamlc: ${OCAMLC}"

# Input: the JSOO classic benchmark sources wrapped in unique modules and
# replicated REPLICAS times (linear; 30 is ~8s on a slow machine). Gitignored.
JSOO_BENCH="${MONOREPO_DIR}/duniverse/js_of_ocaml/benchmarks/sources/ml"
WORKLOAD="${BENCH_DIR}/inputs/compile_workload.ml"
REPLICAS="${OCAMLC_SELF_COMPILE_REPLICAS:-30}"

if [[ ! -d "${JSOO_BENCH}" ]]; then
  echo "ERROR: JSOO benchmark sources not found at ${JSOO_BENCH}" >&2
  echo "  (expected duniverse/js_of_ocaml/benchmarks/sources/ml)" >&2
  exit 1
fi

# Regenerate if a source is newer or REPLICAS changed (sentinel in line 1).
NEEDS_REGEN=0
if [[ ! -f "${WORKLOAD}" ]]; then
  NEEDS_REGEN=1
elif ! head -1 "${WORKLOAD}" 2>/dev/null | grep -q "REPLICAS=${REPLICAS}"; then
  NEEDS_REGEN=1
else
  for f in "${JSOO_BENCH}"/*.ml; do
    if [[ "$f" -nt "${WORKLOAD}" ]]; then NEEDS_REGEN=1; break; fi
  done
fi

if (( NEEDS_REGEN )); then
  echo "  generating compile_workload.ml (REPLICAS=${REPLICAS})..."
  mkdir -p "${BENCH_DIR}/inputs"
  python3 - "${JSOO_BENCH}" "${WORKLOAD}" "${REPLICAS}" <<'PY'
import os, glob, sys
src_dir, dst, replicas = sys.argv[1], sys.argv[2], int(sys.argv[3])
files = sorted(glob.glob(f"{src_dir}/*.ml"))
out = [f"(* GENERATED — REPLICAS={replicas}; do not edit. *)"]
for rep in range(replicas):
    for path in files:
        base = os.path.splitext(os.path.basename(path))[0]
        # Sanitize to a valid OCaml module name.
        clean = "".join(c if c.isalnum() else "_" for c in base)
        modname = (clean[0].upper() + clean[1:]) + f"_{rep}"
        body = open(path).read()
        out.append(f"module {modname} = struct")
        out.append(body)
        out.append("end")
open(dst, "w").write("\n".join(out) + "\n")
PY
  echo "  generated: $(wc -l < "${WORKLOAD}") lines."
else
  echo "  compile_workload.ml is up to date."
fi

# Stage ocamlc.opt under a unique name: running-ng's pid_is_benchmark filter
# rejects /proc/<pid>/exe basenames in BUILD_TOOLS ("ocamlc", "ocamlc.opt"), so
# runtime-events attach would fail on the real binary. Hardlink avoids a 16 MB copy.
OCAMLC_REAL="$(readlink -f "${OCAMLC}")"
STAGED_OCAMLC="${BENCH_DIR}/ocamlc_self_compile_bin-${RUNTIME_TAG}"
# rm first: if the stale link already points at this ocamlc.opt, both ln -f and
# cp -f refuse with "are the same file".
rm -f "${STAGED_OCAMLC}"
ln -f "${OCAMLC_REAL}" "${STAGED_OCAMLC}" 2>/dev/null \
  || cp -f "${OCAMLC_REAL}" "${STAGED_OCAMLC}"
echo "  staged ocamlc binary: ${STAGED_OCAMLC}"

# Some builds (5.5-beta d8bb46c) resolve stdlib relative to argv[0], so the
# relocated binary fails with "Unbound module Stdlib" unless OCAMLLIB is pinned.
OCAMLLIB_DIR="$(${OCAMLC} -where)"
echo "  OCAMLLIB pin:         ${OCAMLLIB_DIR}"

# Wrapper: -o into a scratch dir but no cd, since running-ng resolves
# OCAML_RUNTIME_EVENTS_DIR and friends relative to the cwd it launched us in.
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
WORK_TMPDIR="\$(mktemp -d -t ocamlc_self_compile.XXXXXX)"
trap 'rm -rf "\$WORK_TMPDIR"' EXIT
export OCAMLLIB="${OCAMLLIB_DIR}"
exec "${STAGED_OCAMLC}" -c "${WORKLOAD}" -o "\$WORK_TMPDIR/out.cmo"
WRAPPER
chmod +x "${OUT}"

echo "ocamlc-self-compile wrapper: ${OUT}"
