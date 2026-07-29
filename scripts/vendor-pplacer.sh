#!/usr/bin/env bash
# vendor-pplacer.sh — clone pplacer + mcl and build mcl C libraries.
#
# pplacer is not in opam, so we vendor it manually.  The mcl submodule
# provides a C library (Markov Cluster Algorithm) that must be pre-built
# before dune can link against it.
#
# System dependency: libgsl-dev, libsqlite3-dev, zlib1g-dev
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
PPLACER_DIR="${VENDOR_DIR}/pplacer"

# src_field / clone_pinned — versions and commits come from sources.yml.
source "${MONOREPO_DIR}/scripts/lib-sources.sh"

# Both clones are pinned by commit, and clone_pinned is a no-op when the checkout
# is already at the pin — so this whole script is cheap to re-run. It re-clones
# when a pin is bumped in sources.yml, which the old "does the directory exist?"
# check could not detect.
echo "Vendoring pplacer (pinned)..."
clone_pinned pplacer "${PPLACER_DIR}"
rm -rf "${PPLACER_DIR}/docs/_build"

# mcl is a git submodule declared with an SSH URL upstream; clone over HTTPS
# ourselves instead. It lives inside pplacer's tree, so it has to come second.
echo "Vendoring mcl (pplacer submodule, pinned)..."
clone_pinned mcl "${PPLACER_DIR}/mcl"

# Build mcl C libraries (autotools → static .a archives). Skipped when they are
# already present, so a re-run of an unchanged pin costs nothing.
if [ ! -f "${PPLACER_DIR}/mcl/src/mcl/libmcl.a" ]; then
  echo "Building mcl C libraries..."
  (cd "${PPLACER_DIR}/mcl" && ./configure --quiet && make -j"$(nproc)" --quiet)
else
  echo "  mcl C libraries already built. Skipping."
fi

# Verify the expected static libraries exist
for lib in src/mcl/libmcl.a src/impala/libimpala.a src/clew/libclew.a util/libutil.a; do
  if [ ! -f "${PPLACER_DIR}/mcl/${lib}" ]; then
    echo "ERROR: ${lib} not found after mcl build" >&2
    exit 1
  fi
done

echo "Done.  pplacer vendored to vendor/pplacer/"
echo "  mcl C libraries built in vendor/pplacer/mcl/"
