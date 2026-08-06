#!/usr/bin/env bash
# infer.build.sh — build the java-only Infer static analyzer and emit its
# benchmark wrapper.  Mirrors benchmarks/goblint/goblint.build.sh (per-runtime
# non-dune prefix + hermetic in-tree dune build), except the non-dune deps are
# javalib + sawja (scripts/vendor-javalib-sawja.sh) rather than apron.
#
# Infer itself is vendored manually (vendor/infer, via scripts/vendor-infer.sh):
# its upstream build is autoconf+make that *generates* dune files, so it can't
# join the opam-monorepo lock; instead a java-only pre-generated dune overlay is
# laid down at vendor time and it builds as an ordinary in-tree dune project.
#
# WORKLOAD.  Infer's *multicore* (domains, shared-heap) analysis of a fixed
# subset of a real Java corpus.  Bytecode capture (javalib, JVM-free) is done
# here at build time; the emitted wrapper runs ONLY `infer analyze --multicore`
# on a fresh copy of that capture, so running-ng measures the shared-heap
# parallel analysis — the mode where olly/runtime_events sees all GC activity in
# one process.  Capture and analyze use the SAME per-runtime binary, so the
# marshalled capture DB never crosses an OCaml-version boundary.
#
# TUNING.  Workload size = the rung's roots subset (benchmarks/infer/roots_<rung>.idx),
# a committed slice of the corpus's ~11k classes.  small/default/large hold
# 72/215/542 roots (warm -j12 ~9/16/44s on a 32-core box; the full corpus is ~20x
# the large rung, so there is years of headroom).  To retune for a farm, resample
# each rung:
#   infer debug --source-files -o <capture> | grep '\.class$' | sort \
#     | awk 'NR % K == 1' > benchmarks/infer/roots_<rung>.idx
# and pick K per rung so its wall lands where you want.  Parallelism is INFER_JOBS
# (default 12); a fork/parmap wall-clock companion is INFER_MULTICORE=0.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/infer-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
SAFE_TAG="${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
BUILD_DIR="${MONOREPO_DIR}/_build-${SAFE_TAG}"
JS_PREFIX="${MONOREPO_DIR}/vendor/.infer-js-prefix-${SAFE_TAG}"
CORPUS="${MONOREPO_DIR}/vendor/.infer-corpus/corpus.jar"
CAPTURE="${MONOREPO_DIR}/vendor/.infer-capture-${SAFE_TAG}"
# Input-size ladder: the rung is baked into the output name (small/default/large),
# each selecting a committed roots subset (roots_<rung>.idx — a sampled slice of the
# ~11k-class corpus). More roots = more procedures analysed = more shared-heap
# allocation + multicore GC, at a flat capture footprint. Warm walls at -j12 on a
# 32-core box: small ~9s (72 roots), default ~16s (215), large ~44s (542); a cold
# first analysis is ~2-2.5x. Retune counts per farm by resampling (see the doc page).
case "$(basename "${OUT}")" in
  *infer_small*) ROOTS="${BENCH_DIR}/roots_small.idx" ;;
  *infer_large*) ROOTS="${BENCH_DIR}/roots_large.idx" ;;
  *)             ROOTS="${BENCH_DIR}/roots_default.idx" ;;
esac
JOBS="${INFER_JOBS:-12}"

echo "Building infer (monorepo) for runtime: ${RUNTIME_TAG}"

# 0. Vendored Infer source (idempotent; normally done by setup-monorepo.sh).
[ -f "${MONOREPO_DIR}/vendor/infer/infer/src/infer.ml" ] \
  || bash "${MONOREPO_DIR}/scripts/vendor-infer.sh"

# 1. Corpus jars (runtime-independent; fetch + merge once).
[ -f "${CORPUS}" ] || bash "${MONOREPO_DIR}/scripts/vendor-infer-corpus.sh"

# 2. Per-runtime javalib/sawja prefix (opam-free; only the active compiler).
JS_SRC="${MONOREPO_DIR}/vendor/.infer-js-src" JS_PREFIX="${JS_PREFIX}" \
  bash "${MONOREPO_DIR}/scripts/vendor-javalib-sawja.sh"

# 3. Hermetic dune build of infer.exe.  The duniverse deps (core, atdgen, ...)
#    come from the in-tree dune workspace; only the javalib/sawja prefix is
#    exposed via OCAMLPATH (all C stubs are statically linked, so the wrapper
#    needs no runtime library path).
#
#    extlib + camlzip/zip collision: javalib/sawja link extlib and zip, which
#    the prefix supplies (built by vendor-javalib-sawja.sh).  But the duniverse
#    ALSO ships extlib (ocaml-extlib) and zip (camlzip) because devkit depends
#    on them, and dune rejects two libraries with the same public name in one
#    build ("Conflict between the following libraries: extlib ...").  The clash
#    is *only* visible while this prefix is on OCAMLPATH — devkit's own build
#    never sets it, so it always sees the duniverse copies.  We therefore hide
#    the duniverse duplicates for the duration of infer's build and restore
#    them on exit (same source/version as the prefix copies, so nothing else
#    is affected).  A trap restores them even if the build fails or is killed.
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

# 4. Capture the corpus once with THIS runtime's binary (JVM-free: javalib
#    parses .class directly).  Verified: analyze is READ-ONLY on the 251 MB
#    capture.db (freshly_captured stays set), so the wrapper re-analyses in
#    place with no per-run copy.  Cached across the three ladder rungs (which
#    share this per-runtime capture) — re-captured only when infer.exe is newer
#    than the capture, i.e. after an actual rebuild of this runtime's binary.
if [ ! -d "${CAPTURE}" ] || [ "${REAL_EXE}" -nt "${CAPTURE}" ]; then
  rm -rf "${CAPTURE}"
  "${REAL_EXE}" capture -o "${CAPTURE}" \
    --generated-classes "${CORPUS}" --classpath "${CORPUS}" >/dev/null 2>&1
fi

# 5. Emit the wrapper: analyze the roots subset IN PLACE.  --changed-files-index
#    re-invalidates + re-analyses the roots on every run (no incremental skip),
#    so each measured run is a full cold analysis (verified stable across runs).
MC_FLAG="--multicore"; [ "${INFER_MULTICORE:-1}" = "0" ] && MC_FLAG=""
mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "${REAL_EXE}" analyze ${MC_FLAG} --jobs "\${INFER_JOBS:-${JOBS}}" \\
  --changed-files-index "${ROOTS}" -o "${CAPTURE}"
WRAPPER
chmod +x "${OUT}"

echo "infer built: ${OUT}  (analyze ${MC_FLAG:-fork} -j${JOBS} over $(grep -c . "${ROOTS}") roots)"
