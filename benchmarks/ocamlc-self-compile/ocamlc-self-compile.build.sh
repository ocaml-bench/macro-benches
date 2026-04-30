#!/usr/bin/env bash
# ocamlc-self-compile.build.sh — single-process compiler-throughput benchmark.
#
# Invokes the runtime-under-test's own `ocamlc` (bytecode compiler) on a
# generated input file. The runtime is exercised by *executing ocamlc's
# own code* — ocamlc is a real OCaml application, and the workload it
# performs (parse, type-check, compile to bytecode) genuinely uses
# ephemerons (typing/btype.ml), Hashtbl, and Marshal (.cmi writing).
#
# Bytecode compilation is chosen over native (`ocamlopt`) deliberately:
# ocamlopt with flambda runs *more* compiler passes than baseline, so
# wall time across variants would conflate "runtime perf" with
# "flambda does extra work". With ocamlc, the workload is uniform
# across all flag combos and cross-variant deltas reflect runtime
# performance only.
#
# Closes the Ephemeron and Marshal coverage gaps documented in
# running-ng/docs/benchmark-coverage-gaps-plan.md (Phase 1).
#
# Note: this benchmark builds nothing via dune. The only "build" step
# is generating the input .ml from the JSOO benchmark sources and
# emitting a wrapper script at ${OUT}.

set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/ocamlc_self_compile-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"

echo "Building ocamlc-self-compile benchmark for runtime: ${RUNTIME_TAG}"

# ----------------------------------------------------------------------
# 1. Locate the runtime's ocamlc.
#
# Each variant has its own opam switch named running-ng-${RUNTIME_TAG}.
# We want THAT variant's ocamlc, not the tools switch's ocamlc.
# ----------------------------------------------------------------------
OCAMLC="${HOME}/.opam/running-ng-${RUNTIME_TAG}/bin/ocamlc"
if [[ ! -x "${OCAMLC}" ]]; then
  echo "ERROR: ocamlc not found at ${OCAMLC}" >&2
  echo "  (expected ~/.opam/running-ng-<RUNTIME_TAG>/bin/ocamlc)" >&2
  exit 1
fi
echo "  using ocamlc: ${OCAMLC}"

# ----------------------------------------------------------------------
# 2. Generate the input.
#
# Concatenates the 20 JSOO classic benchmark .ml files (boyer, nucleic,
# raytrace, kb, fft, ...) — these are well-known compile-stress
# benchmarks from the OCaml testsuite — wrapped in unique modules and
# replicated REPLICAS times. Linear scaling.
#
# Tune REPLICAS for the target wall time. 30 → ~8s on a slow machine
# at ocamlc bytecode (roughly proportional on faster hardware).
# Output is gitignored. Regenerated only when sources change.
# ----------------------------------------------------------------------
JSOO_BENCH="${MONOREPO_DIR}/duniverse/js_of_ocaml/benchmarks/sources/ml"
WORKLOAD="${BENCH_DIR}/inputs/compile_workload.ml"
REPLICAS="${OCAMLC_SELF_COMPILE_REPLICAS:-30}"

if [[ ! -d "${JSOO_BENCH}" ]]; then
  echo "ERROR: JSOO benchmark sources not found at ${JSOO_BENCH}" >&2
  echo "  (expected duniverse/js_of_ocaml/benchmarks/sources/ml)" >&2
  exit 1
fi

# Need to regenerate if any source file is newer than the workload, or
# if REPLICAS changed (we encode it in a sentinel comment at the top).
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
        # Sanitize to a valid OCaml module name: capitalised, only
        # [A-Za-z0-9_], with the replica index appended.
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

# ----------------------------------------------------------------------
# 3. Stage a renamed copy of ocamlc.opt.
#
# running-ng's pid_is_benchmark filter rejects any /proc/<pid>/exe whose
# basename is in BUILD_TOOLS (which includes "ocamlc" / "ocamlc.opt") — a
# guard for transient compiler subprocesses inside *other* benchmarks'
# wrappers. Here ocamlc IS the benchmark, so we hardlink (or copy) the
# real ocamlc.opt to a uniquely-named binary so /proc/<pid>/exe basename
# is `ocamlc_self_compile_bin-<RUNTIME_TAG>` and runtime-events attach
# succeeds. The hardlink avoids a 16 MB copy when the destination is on
# the same filesystem.
# ----------------------------------------------------------------------
OCAMLC_REAL="$(readlink -f "${OCAMLC}")"  # follow ocamlc → ocamlc.opt
STAGED_OCAMLC="${BENCH_DIR}/ocamlc_self_compile_bin-${RUNTIME_TAG}"
ln -f "${OCAMLC_REAL}" "${STAGED_OCAMLC}" 2>/dev/null \
  || cp -f "${OCAMLC_REAL}" "${STAGED_OCAMLC}"
echo "  staged ocamlc binary: ${STAGED_OCAMLC}"

# ----------------------------------------------------------------------
# 4. Emit the wrapper script.
#
# At run time:
#   - Output .cmi/.cmo to a wrapper-owned scratch dir via -o (so the
#     source tree stays clean), but DO NOT cd — the OCaml process must
#     keep running-ng's cwd so OCAML_RUNTIME_EVENTS_DIR resolution and
#     anything else relative to cwd behave as running-ng expects.
#   - exec the staged (renamed) ocamlc binary.
# ----------------------------------------------------------------------
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
WORK_TMPDIR="\$(mktemp -d -t ocamlc_self_compile.XXXXXX)"
trap 'rm -rf "\$WORK_TMPDIR"' EXIT
exec "${STAGED_OCAMLC}" -c "${WORKLOAD}" -o "\$WORK_TMPDIR/out.cmo"
WRAPPER
chmod +x "${OUT}"

echo "ocamlc-self-compile wrapper: ${OUT}"
