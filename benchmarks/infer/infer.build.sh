#!/usr/bin/env bash
# infer.build.sh: build the java-only Infer analyzer (vendor/infer, dune overlay
# laid down by scripts/vendor-infer.sh) and emit a wrapper that runs
# `infer analyze --multicore` on a Java corpus captured here (javalib, JVM-free)
# with the same per-runtime binary, so the marshalled capture DB never crosses
# an OCaml version. Knobs: INFER_JOBS (default 12); INFER_MULTICORE=0 for fork/parmap.
# Retune a rung: infer debug --source-files -o <capture> | grep '\.class$' | sort \
#   | awk 'NR % K == 1' > benchmarks/infer/roots_<rung>.idx
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/infer-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
SAFE_TAG="${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
BUILD_DIR="${MONOREPO_DIR}/_build-${SAFE_TAG}"
JS_PREFIX="${MONOREPO_DIR}/vendor/.infer-js-prefix-${SAFE_TAG}"
CORPUS="${MONOREPO_DIR}/vendor/.infer-corpus/corpus.jar"
CAPTURE="${MONOREPO_DIR}/vendor/.infer-capture-${SAFE_TAG}"
# The rung in the output name selects a committed roots subset; more roots means
# more procedures analysed at a flat capture footprint (72/215/542 roots ~9/16/44s at -j12).
case "$(basename "${OUT}")" in
  *infer_small*) ROOTS="${BENCH_DIR}/roots_small.idx" ;;
  *infer_large*) ROOTS="${BENCH_DIR}/roots_large.idx" ;;
  *)             ROOTS="${BENCH_DIR}/roots_default.idx" ;;
esac
JOBS="${INFER_JOBS:-12}"

echo "Building infer (monorepo) for runtime: ${RUNTIME_TAG}"

[ -f "${MONOREPO_DIR}/vendor/infer/infer/src/base/Version.ml" ] \
  || bash "${MONOREPO_DIR}/scripts/vendor-infer.sh"

[ -f "${CORPUS}" ] || bash "${MONOREPO_DIR}/scripts/vendor-infer-corpus.sh"

JS_SRC="${MONOREPO_DIR}/vendor/.infer-js-src" JS_PREFIX="${JS_PREFIX}" \
  bash "${MONOREPO_DIR}/scripts/vendor-javalib-sawja.sh"

# Hide the duniverse extlib/camlzip during the build: the javalib/sawja prefix
# on OCAMLPATH ships the same libraries and dune rejects the duplicate ("Conflict
# between the following libraries: extlib ..."). Restored on exit, even on failure.
unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH="${JS_PREFIX}/lib"

_INFER_HIDDEN_DIR="$(mktemp -d "${MONOREPO_DIR}/vendor/.infer-hidden-dups.XXXXXX")"
_infer_restore_dups() {
  for d in ocaml-extlib camlzip; do
    [ -d "${_INFER_HIDDEN_DIR}/${d}" ] && [ ! -e "${MONOREPO_DIR}/duniverse/${d}" ] \
      && mv "${_INFER_HIDDEN_DIR}/${d}" "${MONOREPO_DIR}/duniverse/${d}"
  done
  rmdir "${_INFER_HIDDEN_DIR}" 2>/dev/null || true
}
trap _infer_restore_dups EXIT
for d in ocaml-extlib camlzip; do
  [ -d "${MONOREPO_DIR}/duniverse/${d}" ] \
    && mv "${MONOREPO_DIR}/duniverse/${d}" "${_INFER_HIDDEN_DIR}/${d}"
done

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" --profile release \
  vendor/infer/infer/src/infer.exe

_infer_restore_dups
trap - EXIT
REAL_EXE="${BUILD_DIR}/default/vendor/infer/infer/src/infer.exe"

# Capture once per runtime (shared by the rungs, redone when infer.exe is newer).
# analyze is read-only on capture.db, so the wrapper re-analyses in place.
if [ ! -d "${CAPTURE}" ] || [ "${REAL_EXE}" -nt "${CAPTURE}" ]; then
  rm -rf "${CAPTURE}"
  "${REAL_EXE}" capture -o "${CAPTURE}" \
    --generated-classes "${CORPUS}" --classpath "${CORPUS}" >/dev/null 2>&1
fi

# --changed-files-index re-analyses the roots on every run (no incremental skip).
MC_FLAG="--multicore"; [ "${INFER_MULTICORE:-1}" = "0" ] && MC_FLAG=""
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
# --no-progress-bar: infer's progress bar style is "auto", which resolves to
# "multiline" only on a tty. running-ng redirects to a log file, so it falls to
# "plain", which prints "<class> starting" / "<class> DONE" per analysed class
# through Logging.task_progress. On the large rung that is ~13M lines --
# ~780 MB of benchmark log per invocation (a single sweep wrote 23 GB and filled
# the host's disk), plus the write I/O inside the measured region. Measured on
# the small rung, 3 interleaved pairs: console 7.8/4.0/8.3 MB -> 0, no wall-clock
# difference, and report.json identical, so the analysis is unchanged.
# --jobs follows the CPUs we were actually given, not a number baked in at
# build time.  nproc reports the size of the process's affinity mask, so under
# running-ng's pinning this is exactly the benchmark's core count, and
# DomainPool (patched in scripts/vendor-infer.sh) then places one domain per
# CPU.  Asking for more domains than cores is measurably worse once placement
# is static: on a 2-core mask, --jobs 8 took 54.91s at 156% CPU against 43.11s
# at 192% for --jobs 2.  INFER_JOBS still overrides, and the build-time default
# survives as the fallback where nproc is absent (coreutils, so not everywhere
# outside Linux).
exec "${REAL_EXE}" analyze ${MC_FLAG} --no-progress-bar \\
  --jobs "\${INFER_JOBS:-\$(nproc 2>/dev/null || echo ${JOBS})}" \\
  --changed-files-index "${ROOTS}" -o "${CAPTURE}"
WRAPPER
chmod +x "${OUT}"

echo "infer built: ${OUT}  (analyze ${MC_FLAG:-fork} -j${JOBS} over $(grep -c . "${ROOTS}") roots)"
