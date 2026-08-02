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

# Install the Knob-A likelihood-ladder driver (dune-overlays/pplacer/like_bench.ml)
# and register it in the cloned dune's executables stanza. like_bench.ml is a
# macro-benches addition (pplacer's Felsenstein likelihood hot path, lifted from
# tests/pplacer/test_like.ml) that vendor/ — being gitignored — cannot hold, so
# it lives tracked under dune-overlays/ and is copied in on every (re-)vendor.
# The dune edit is idempotent: skipped once `like_bench` is already registered.
echo "Installing like_bench Knob-A driver overlay..."
cp "${MONOREPO_DIR}/dune-overlays/pplacer/like_bench.ml" "${PPLACER_DIR}/like_bench.ml"
if ! grep -q 'like_bench' "${PPLACER_DIR}/dune"; then
  sed -i \
    -e 's/(names pplacer guppy rppr tests)/(names pplacer guppy rppr tests like_bench)/' \
    -e 's/(public_names pplacer guppy rppr -)/(public_names pplacer guppy rppr - -)/' \
    "${PPLACER_DIR}/dune"
fi
if ! grep -q 'like_bench' "${PPLACER_DIR}/dune"; then
  echo "ERROR: failed to register like_bench in ${PPLACER_DIR}/dune" >&2
  exit 1
fi

echo "Done.  pplacer vendored to vendor/pplacer/"
echo "  mcl C libraries built in vendor/pplacer/mcl/"
echo "  like_bench Knob-A driver installed + registered in dune."
