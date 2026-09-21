#!/usr/bin/env bash
# Clone Infer into vendor/infer for a java-only, pure-dune build. Infer's own
# build is autoconf + make that generates its dune files, and its configure
# asserts deps are installed, so instead: clone the pin, drop its
# dune-workspace, neutralize every *.opam (deps are declared in dune-project's
# macro-bench-infer) and copy the pre-generated java-only dune files from
# dune-overlays/infer/ (darwin=false pinned, so flags are identical across runtimes).
#
# To regenerate the overlay when bumping the pin: configure a checkout java-only
# (./build-infer.sh java), copy the generated infer/src/{dune,dune.common,
# unit/dune,integration/dune,integration/unit/dune,java/dune,opensource/dune} and
# infer/src/base/Version.ml into dune-overlays/infer/, set `let darwin = false`.
set -euo pipefail

INFER_URL="${INFER_URL:-https://github.com/ngorogiannis/infer.git}"
INFER_REF="${INFER_REF:-inferbench-v1.1}"

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
INFER_DIR="${VENDOR_DIR}/infer"
OVERLAY_DIR="${MONOREPO_DIR}/dune-overlays/infer"

# The pin comes from sources.yml; INFER_URL/INFER_REF above are informational only.
source "${MONOREPO_DIR}/scripts/lib-sources.sh"

# The sentinel is the overlay-only Version.ml, not a cloned file, so a vendoring
# that aborted part-way re-runs instead of looking done.
if [ -f "${INFER_DIR}/infer/src/base/Version.ml" ]; then
  echo "vendor/infer/ already exists. Remove it first to re-vendor."
  exit 0
fi

echo "Cloning Infer (pinned in sources.yml)..."
mkdir -p "${VENDOR_DIR}"
clone_pinned infer "${INFER_DIR}"
# Drop .git: vendor/infer is a self-contained, patched tree, not a live checkout.
rm -rf "${INFER_DIR}/.git"

# Never built: the C++ clang plugin, docs, sledge (swift).
rm -rf \
  "${INFER_DIR}/facebook-clang-plugins" \
  "${INFER_DIR}/website" \
  "${INFER_DIR}/docker" \
  "${INFER_DIR}/examples" \
  "${INFER_DIR}/sledge" \
  "${INFER_DIR}/_build" \
  "${INFER_DIR}"/_build_logs 2>/dev/null || true

# opam-monorepo scans the whole tree: infer/opam/*.opam duplicate infer/infer.opam
# ("defined multiple times"), and bin/infer-* are dangling symlinks it cannot stat.
rm -rf "${INFER_DIR}/opam"
find "${INFER_DIR}" -xtype l -delete 2>/dev/null || true

# The java-only exe still links ClangFrontend (pure OCaml), so infer/src/clang
# stays; these four are not linked.
for d in python rust erlang swift; do
  rm -rf "${INFER_DIR}/infer/src/${d}" 2>/dev/null || true
done

# The monorepo root owns the dune workspace.
rm -f "${INFER_DIR}/infer/dune-workspace"

# Neutralize every *.opam so opam-monorepo ignores Infer as a package (as
# vendor-frama-c.sh does).
while IFS= read -r f; do
  printf 'opam-version: "2.0"\n' > "$f"
done < <(find "${INFER_DIR}" -name '*.opam')

if [ ! -d "${OVERLAY_DIR}" ]; then
  echo "ERROR: missing dune-overlays/infer/ (the pre-generated java-only dune files)." >&2
  exit 1
fi
cp -R "${OVERLAY_DIR}/infer/." "${INFER_DIR}/infer/"

# IssueType.ml/Checker.ml embed docs via [%blob "./documentation/..."]; upstream
# src/base/documentation is a symlink, which dune's sandbox does not bridge for
# the blob path. Replace it with a real copy (the overlay's base/dune globs
# documentation/*.md).
if [ -L "${INFER_DIR}/infer/src/base/documentation" ]; then
  rm -f "${INFER_DIR}/infer/src/base/documentation"
fi
rm -rf "${INFER_DIR}/infer/src/base/documentation"
cp -R "${INFER_DIR}/infer/documentation" "${INFER_DIR}/infer/src/base/documentation"

# Logging.task_progress logs two lines per analysed procedure, to the console
# (bar `Plain`, chosen whenever stdout is not a tty) or to the results-dir logs
# file: ~13M lines per large invocation, inside the measured region (one sweep
# filled a disk with 31 GB). Skip both when the bar is `Quiet` (--no-progress-bar).
LOGGING_ML="${INFER_DIR}/infer/src/base/Logging.ml"
if grep -q 'MACRO_BENCHES_QUIET_TASK_PROGRESS' "${LOGGING_ML}" 2>/dev/null; then
  echo "  Logging.task_progress: already patched."
elif grep -q '^let task_progress ~f pp x =$' "${LOGGING_ML}" 2>/dev/null; then
  python3 - "${LOGGING_ML}" <<'PATCH_EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """let task_progress ~f pp x =
  log_task "%a starting@." pp x ;
  let result = f () in
  log_task "%a DONE@." pp x ;
  result"""
new = """(* MACRO_BENCHES_QUIET_TASK_PROGRESS: see scripts/vendor-infer.sh *)
let task_progress ~f pp x =
  match Config.progress_bar with
  | `Quiet ->
      f ()
  | `Plain | `MultiLine ->
      log_task "%a starting@." pp x ;
      let result = f () in
      log_task "%a DONE@." pp x ;
      result"""
assert s.count(old) == 1, "task_progress not matched -- patch me"
open(p, "w").write(s.replace(old, new))
PATCH_EOF
  echo "  Patched Logging.task_progress (no per-procedure logging when quiet)."
else
  echo "ERROR: Logging.task_progress not found in its expected shape -- patch me." >&2
  exit 1
fi

# DomainPool leaves domain placement to the kernel; with `isolcpus=` there is
# no load balancing and every domain lands on one core (87.9s at 100% CPU vs
# 26.3s at 330% pinned). Place one worker per CPU of the inherited mask, as
# lavyek_bench.ml does; Affinity.get_ids/set_ids are direct pthread affinity
# externals, so this also holds on FreeBSD and ARM.
INFER_DOMAINPOOL="${INFER_DIR}/infer/src/base/DomainPool.ml"
if grep -q 'MACRO_BENCHES_DOMAIN_PINNING' "${INFER_DOMAINPOOL}" 2>/dev/null; then
  echo "  DomainPool domain pinning: already patched."
elif grep -q '^let child ~f ~child_prologue ~child_epilogue ~command_queue ~message_queue worker_id =$' "${INFER_DOMAINPOOL}" 2>/dev/null; then
  python3 - "${INFER_DOMAINPOOL}" <<'PATCH_EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """let child ~f ~child_prologue ~child_epilogue ~command_queue ~message_queue worker_id =
  Printexc.record_backtrace true ;"""
new = """(* MACRO_BENCHES_DOMAIN_PINNING: see scripts/vendor-infer.sh.

   Read once, here in the main domain, before any worker narrows its own mask:
   Processor.Affinity.get_ids reports the CPUs of the CALLING thread, so a
   worker asking after it had pinned itself would see just its own CPU. *)
let macro_benches_pin_cpus = Array.of_list (Processor.Affinity.get_ids ())

let macro_benches_pin_worker worker_id =
  let n = Array.length macro_benches_pin_cpus in
  (* Nothing to spread over with one CPU, and nothing to place with none (the
     affinity calls are a no-op on macOS, which reports an empty list). *)
  if n > 1 then
    try Processor.Affinity.set_ids [macro_benches_pin_cpus.(Int.rem worker_id n)]
    with exn -> L.internal_error "could not pin worker %d: %a@." worker_id Exn.pp exn


let child ~f ~child_prologue ~child_epilogue ~command_queue ~message_queue worker_id =
  macro_benches_pin_worker worker_id ;
  Printexc.record_backtrace true ;"""
assert s.count(old) == 1, "DomainPool.child not matched -- patch me"
open(p, "w").write(s.replace(old, new))
PATCH_EOF
  echo "  Patched DomainPool (one analysis domain per CPU of the inherited mask)."
else
  echo "ERROR: DomainPool.child not found in its expected shape -- patch me." >&2
  exit 1
fi

echo "Done.  Infer ${INFER_REF} vendored to vendor/infer/ (java-only, pure-dune)."
echo "  Build the exe with: dune build vendor/infer/infer/src/infer.exe"
