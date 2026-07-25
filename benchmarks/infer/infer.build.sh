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
# TUNING.  Workload size = benchmarks/infer/roots.idx, a fixed committed subset
# of the corpus's ~11k classes (~72 -> ~15s at -j12 on a fast 12+-core box; the
# full corpus is ~24x larger).  To retune for this farm, regenerate roots.idx:
#   infer debug --source-files -o <capture> | grep '\.class$' | sort \
#     | awk 'NR % K == 1' > benchmarks/infer/roots.idx
# and pick K so the wrapper lands in the 5-25s band.  Parallelism is INFER_JOBS
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
ROOTS="${BENCH_DIR}/roots.idx"
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
unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH="${JS_PREFIX}/lib"
dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" --profile release \
  vendor/infer/infer/src/infer.exe
REAL_EXE="${BUILD_DIR}/default/vendor/infer/infer/src/infer.exe"

# 4. Capture the corpus once with THIS runtime's binary (JVM-free: javalib
#    parses .class directly).  Verified: analyze is READ-ONLY on the 251 MB
#    capture.db (freshly_captured stays set), so the wrapper re-analyses in
#    place with no per-run copy.
rm -rf "${CAPTURE}"
"${REAL_EXE}" capture -o "${CAPTURE}" \
  --generated-classes "${CORPUS}" --classpath "${CORPUS}" >/dev/null 2>&1

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
