#!/usr/bin/env bash
# Clone pplacer + mcl and build the mcl C libraries (pplacer is not in opam).
# System deps: libgsl-dev, libsqlite3-dev, zlib1g-dev
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
PPLACER_DIR="${VENDOR_DIR}/pplacer"

source "${MONOREPO_DIR}/scripts/lib-sources.sh"

echo "Vendoring pplacer (pinned)..."
clone_pinned pplacer "${PPLACER_DIR}"
rm -rf "${PPLACER_DIR}/docs/_build"

# mcl is a submodule with an SSH upstream URL; clone over HTTPS instead.
# It lives inside pplacer's tree, so it must come second.
echo "Vendoring mcl (pplacer submodule, pinned)..."
clone_pinned mcl "${PPLACER_DIR}/mcl"

if [ ! -f "${PPLACER_DIR}/mcl/src/mcl/libmcl.a" ]; then
  echo "Building mcl C libraries..."
  # `-s`, not `--quiet`: BSD make rejects the long option.
  (cd "${PPLACER_DIR}/mcl" && ./configure --quiet && make -j"$(ncpu)" -s)
else
  echo "  mcl C libraries already built. Skipping."
fi

for lib in src/mcl/libmcl.a src/impala/libimpala.a src/clew/libclew.a util/libutil.a; do
  if [ ! -f "${PPLACER_DIR}/mcl/${lib}" ]; then
    echo "ERROR: ${lib} not found after mcl build" >&2
    exit 1
  fi
done

# like_bench.ml is a macro-benches addition that gitignored vendor/ cannot hold,
# so it is tracked under dune-overlays/ and copied in on every re-vendor.
echo "Installing like_bench input-size ladder driver overlay..."
cp "${MONOREPO_DIR}/dune-overlays/pplacer/like_bench.ml" "${PPLACER_DIR}/like_bench.ml"
if ! grep -q 'like_bench' "${PPLACER_DIR}/dune"; then
  sed_i \
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
echo "  like_bench input-size ladder driver installed + registered in dune."
