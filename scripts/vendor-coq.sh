#!/usr/bin/env bash
# vendor-coq.sh — download and extract rocq (Coq) + zarith into vendor/.
#
# Zarith uses configure/make, not dune.  A hand-written dune overlay is
# installed so it builds inside the monorepo workspace.
#
# System dependency: libgmp-dev (for zarith).
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
DUNE_OVERLAY_DIR="${MONOREPO_DIR}/dune-overlays"

# --- zarith (arbitrary-precision arithmetic, GMP wrapper) ---
ZARITH_VERSION="1.14"
ZARITH_URL="https://github.com/ocaml/Zarith/archive/refs/tags/release-${ZARITH_VERSION}.tar.gz"
ZARITH_MD5="05ef6f78ebea92aa5c3ff35bbfd29bf9"

# --- rocq (Coq proof assistant, renamed to Rocq in 9.0) ---
ROCQ_VERSION="9.0.0"
ROCQ_URL="https://github.com/rocq-prover/rocq/archive/refs/tags/V${ROCQ_VERSION}.tar.gz"
ROCQ_MD5="e6c2f84353384300a47b2e90d6824229"

# ---- helpers ----
download_and_extract() {
  local name="$1" url="$2" md5="$3" dest="$4"

  if [ -d "${dest}" ]; then
    echo "vendor/${name}/ already exists. Remove it first to re-vendor."
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  echo "Downloading ${name}..."
  curl -fSL "${url}" -o "${tmpdir}/archive.tar.gz"

  local actual_md5
  actual_md5="$(md5sum "${tmpdir}/archive.tar.gz" | cut -d' ' -f1)"
  if [ "${actual_md5}" != "${md5}" ]; then
    echo "MD5 mismatch for ${name}: expected ${md5}, got ${actual_md5}" >&2
    exit 1
  fi

  echo "Extracting ${name}..."
  tar xzf "${tmpdir}/archive.tar.gz" -C "${tmpdir}"

  local extracted
  extracted="$(find "${tmpdir}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | head -1)"
  if [ -z "${extracted}" ]; then
    echo "Failed to find extracted directory for ${name}" >&2
    exit 1
  fi

  mkdir -p "${VENDOR_DIR}"
  mv "${extracted}" "${dest}"
  echo "Vendored ${name} to vendor/${name}/"
}

# ---- check system deps ----
if ! pkg-config --exists gmp 2>/dev/null && [ ! -f /usr/include/gmp.h ]; then
  echo "WARNING: GMP headers not found. Install libgmp-dev for zarith." >&2
fi

# ---- download ----
download_and_extract "zarith" "${ZARITH_URL}" "${ZARITH_MD5}" "${VENDOR_DIR}/zarith"
download_and_extract "rocq" "${ROCQ_URL}" "${ROCQ_MD5}" "${VENDOR_DIR}/rocq"

# ---- install dune overlays ----
# zarith uses configure/make.  Install hand-written dune files.
if [ -d "${DUNE_OVERLAY_DIR}/zarith" ]; then
  echo "Installing dune overlay for zarith..."
  cp "${DUNE_OVERLAY_DIR}/zarith/dune" "${VENDOR_DIR}/zarith/dune"
  cp "${DUNE_OVERLAY_DIR}/zarith/dune-project" "${VENDOR_DIR}/zarith/dune-project"
fi

# rocq uses dune natively but needs dunestrap for .vo theory files.
# For benchmarking we only need the OCaml binaries, so just build coqc.
# Run dunestrap before building:
#   cd vendor/rocq && make dunestrap

echo "Done.  To build:"
echo "  1. cd vendor/rocq && make dunestrap"
echo "  2. dune build vendor/rocq/topbin/coqc_bin.exe --profile release"
echo ""
echo "Note: rocq's theories/dune must be generated via 'make dunestrap'"
echo "before the full dune build will succeed."
