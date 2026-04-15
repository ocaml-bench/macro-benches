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

if [ -d "${PPLACER_DIR}" ] && [ -f "${PPLACER_DIR}/dune" ]; then
  echo "vendor/pplacer/ already exists. Remove it first to re-vendor."
  # Ensure mcl C libraries are built even if pplacer is already vendored
  if [ ! -f "${PPLACER_DIR}/mcl/src/mcl/libmcl.a" ]; then
    echo "  mcl C libraries not found — building..."
    (cd "${PPLACER_DIR}/mcl" && ./configure --quiet && make -j"$(nproc)" --quiet)
    echo "  mcl C libraries built."
  fi
  exit 0
fi

echo "Cloning pplacer..."
git clone --depth=1 https://github.com/matsen/pplacer.git "${PPLACER_DIR}"
rm -rf "${PPLACER_DIR}/.git" "${PPLACER_DIR}/docs/_build"

# mcl is a git submodule that uses SSH URLs; clone via HTTPS instead
echo "Cloning mcl (pplacer submodule)..."
rm -rf "${PPLACER_DIR}/mcl"
git clone --depth=1 https://github.com/fhcrc/mcl.git "${PPLACER_DIR}/mcl"
rm -rf "${PPLACER_DIR}/mcl/.git"

# Build mcl C libraries (autotools → static .a archives)
echo "Building mcl C libraries..."
(cd "${PPLACER_DIR}/mcl" && ./configure --quiet && make -j"$(nproc)" --quiet)

# Verify the expected static libraries exist
for lib in src/mcl/libmcl.a src/impala/libimpala.a src/clew/libclew.a util/libutil.a; do
  if [ ! -f "${PPLACER_DIR}/mcl/${lib}" ]; then
    echo "ERROR: ${lib} not found after mcl build" >&2
    exit 1
  fi
done

echo "Done.  pplacer vendored to vendor/pplacer/"
echo "  mcl C libraries built in vendor/pplacer/mcl/"
