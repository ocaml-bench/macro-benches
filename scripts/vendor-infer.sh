#!/usr/bin/env bash
# vendor-infer.sh — clone Infer source into vendor/infer for a java-only,
# pure-dune macro-benchmark build.
#
# WHY MANUAL VENDORING (like frama-c / pplacer, not opam-monorepo):
# Infer's upstream build is autoconf + make that *generates* its dune files
# from *.in templates (substituting a handful of @BUILD_*_ANALYZERS@ /
# @BUILD_PLATFORM@ booleans) and its ./configure ASSERTS that many OCaml
# packages are already installed (atdgen, javalib, sawja, yojson, ...) and
# probes for external tools (javac, menhir, atdgen).  In the monorepo those
# deps live in duniverse/, not the tools switch, so running ./configure at
# setup would fail.  Instead we:
#   1. clone the source at a pinned ref,
#   2. drop the top-level dune-workspace (the monorepo provides the single
#      workspace/context) but KEEP infer/dune-project so vendor/infer is a
#      self-contained dune project pinning `(lang dune 3.16)` + menhir 3.0,
#   3. neutralize every *.opam in the tree so opam-monorepo does not treat
#      Infer as a local package and try to vendor its (already-declared)
#      deps a second time — the real deps are declared in dune-project's
#      `macro-bench-infer` package,
#   4. lay down a committed set of pre-generated *java-only* dune files
#      (dune-overlays/infer/) — the exact files `./configure && make`
#      produces for a java-only tree, with @BUILD_PLATFORM@ pinned to Linux
#      (darwin=false => -O3 flambda, identical across runtimes).
#
# Regenerating the overlay (only when bumping INFER_REF): configure an Infer
# checkout java-only (./build-infer.sh java) and copy the generated
# infer/src/{dune,dune.common,unit/dune,integration/dune,integration/unit/dune,
# java/dune,opensource/dune} and infer/src/base/Version.ml into
# dune-overlays/infer/, then set `let darwin = false` in dune.common.
#
# The benchmark exe is built by benchmarks/infer/infer.build.sh as
#   dune build vendor/infer/infer/src/infer.exe
set -euo pipefail

# Pinned source: the java-only, OCaml 5.2–5.4 tree, tagged `inferbench-v1.1`.
# Pinned to an immutable release tag (not a branch name) so the benchmark
# source can't shift under us if development branches are later updated.
INFER_URL="${INFER_URL:-https://github.com/ngorogiannis/infer.git}"
INFER_REF="${INFER_REF:-inferbench-v1.1}"

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
INFER_DIR="${VENDOR_DIR}/infer"
OVERLAY_DIR="${MONOREPO_DIR}/dune-overlays/infer"

# clone_pinned — the URL and pinned commit come from sources.yml (`infer` key).
# INFER_URL/INFER_REF above are kept only for the overlay-regeneration comment.
source "${MONOREPO_DIR}/scripts/lib-sources.sh"

# Idempotence sentinel: base/Version.ml, which ONLY the overlay below supplies
# (upstream ships Version.ml.in + Version.mli and generates the .ml via
# ./configure).  Deliberately not a source-tree file like infer/dune-project or
# src/infer.ml: those exist in a bare clone, so if vendoring aborted part-way —
# e.g. clone_pinned rejecting a bad pin — the half-vendored tree would look
# "already vendored" here and the build would fail much later with a confusing
# `(modules_without_implementation version)` dune error.  Keyed on an
# overlay-only file, an interrupted vendoring re-runs and self-heals.
if [ -f "${INFER_DIR}/infer/src/base/Version.ml" ]; then
  echo "vendor/infer/ already exists. Remove it first to re-vendor."
  exit 0
fi

echo "Cloning Infer (pinned in sources.yml)..."
mkdir -p "${VENDOR_DIR}"
clone_pinned infer "${INFER_DIR}"
# Drop .git: vendor/infer is a self-contained, patched tree, not a live checkout.
rm -rf "${INFER_DIR}/.git"

# ---- Strip subtrees we never build (java-only, pure OCaml, no C/C++ frontends) ----
#   facebook-clang-plugins : large C++ clang plugin (clang analyzer only)
#   website / docker / examples / _build_logs : docs, images, artifacts
#   sledge                 : LLVM-based analyzer (swift), not built
rm -rf \
  "${INFER_DIR}/facebook-clang-plugins" \
  "${INFER_DIR}/website" \
  "${INFER_DIR}/docker" \
  "${INFER_DIR}/examples" \
  "${INFER_DIR}/sledge" \
  "${INFER_DIR}/_build" \
  "${INFER_DIR}"/_build_logs 2>/dev/null || true

# opam-monorepo scans the whole vendored tree.  Two things trip it up:
#   - infer/opam/{infer,infer-tests}.opam duplicate infer/infer.opam ("defined
#     multiple times"); drop the opam/ packaging dir, keeping infer/infer.opam
#     (neutralized below) as the single package decl that dune public_names need.
#   - infer/bin/infer-* and infer/lib/wrappers/* are dangling symlinks to the
#     (not-yet-built) infer binary; opam-monorepo errors trying to stat them.
rm -rf "${INFER_DIR}/opam"
find "${INFER_DIR}" -xtype l -delete 2>/dev/null || true

# Disabled-frontend OCaml source dirs.  NOTE: the java-only exe STILL links
# ClangFrontend (infer/src/clang) — analyzer selection drops python/rust/
# erlang/swift from the link line but not clang — so clang MUST be kept (its
# generated dune is supplied by the overlay; its ClangFrontend library is
# pure OCaml, needing no facebook-clang-plugins).  python/rust have no dune
# at all and erlang/swift are already gone, so pruning them is safe.
for d in python rust erlang swift; do
  rm -rf "${INFER_DIR}/infer/src/${d}" 2>/dev/null || true
done

# ---- One dune workspace only: drop Infer's (the monorepo root owns it) ----
rm -f "${INFER_DIR}/infer/dune-workspace"

# ---- Neutralize every *.opam so opam-monorepo ignores Infer as a package ----
# (mirrors scripts/vendor-frama-c.sh's empty-opam fill).  Infer's real deps
# are declared in dune-project's macro-bench-infer package.
while IFS= read -r f; do
  printf 'opam-version: "2.0"\n' > "$f"
done < <(find "${INFER_DIR}" -name '*.opam')

# ---- Lay down the pre-generated java-only dune files + Version.ml ----
if [ ! -d "${OVERLAY_DIR}" ]; then
  echo "ERROR: missing dune-overlays/infer/ (the pre-generated java-only dune files)." >&2
  exit 1
fi
cp -R "${OVERLAY_DIR}/infer/." "${INFER_DIR}/infer/"

# ---- Materialize IBase's ppx_blob docs as a real directory ----
# infer/src/base/IssueType.ml / Checker.ml embed docs via [%blob
# "./documentation/<...>.md"].  Upstream, src/base/documentation is a symlink
# to ../../documentation and base/dune declares the blob files with a
# `../../documentation/*.md` glob.  dune's preprocessing sandbox does not
# bridge the blob's `./documentation` path through that symlink+glob (a
# non-sandboxed in-tree `make` happens to work; a clean sandboxed dune build
# does not).  The overlay's base/dune globs `documentation/*.md` instead, so
# replace the symlink with a real copy for the dep path to match the blob path.
if [ -L "${INFER_DIR}/infer/src/base/documentation" ]; then
  rm -f "${INFER_DIR}/infer/src/base/documentation"
fi
rm -rf "${INFER_DIR}/infer/src/base/documentation"
cp -R "${INFER_DIR}/infer/documentation" "${INFER_DIR}/infer/src/base/documentation"

echo "Done.  Infer ${INFER_REF} vendored to vendor/infer/ (java-only, pure-dune)."
echo "  Build the exe with: dune build vendor/infer/infer/src/infer.exe"
