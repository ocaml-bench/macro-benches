#!/usr/bin/env bash
# Download and extract rocq + zarith into vendor/. zarith is configure/make, so
# a dune overlay from dune-overlays/ is installed. System dep: libgmp-dev.
set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib-sources.sh"

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
DUNE_OVERLAY_DIR="${MONOREPO_DIR}/dune-overlays"

ZARITH_VERSION="$(src_field zarith version)"
ZARITH_URL="$(src_field zarith url)"
ZARITH_MD5="$(src_field zarith md5)"

ROCQ_VERSION="$(src_field rocq version)"
ROCQ_URL="$(src_field rocq url)"
ROCQ_MD5="$(src_field rocq md5)"

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
  actual_md5="$(checksum "${tmpdir}/archive.tar.gz")"
  if [ "${actual_md5}" != "${md5}" ]; then
    echo "MD5 mismatch for ${name}: expected ${md5}, got ${actual_md5}" >&2
    exit 1
  fi

  echo "Extracting ${name}..."
  tar --no-same-owner -xzf "${tmpdir}/archive.tar.gz" -C "${tmpdir}"

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

if ! pkg-config --exists gmp 2>/dev/null && [ ! -f /usr/include/gmp.h ]; then
  echo "WARNING: GMP headers not found. Install libgmp-dev for zarith." >&2
fi

download_and_extract "zarith" "${ZARITH_URL}" "${ZARITH_MD5}" "${VENDOR_DIR}/zarith"
download_and_extract "rocq" "${ROCQ_URL}" "${ROCQ_MD5}" "${VENDOR_DIR}/rocq"

if [ -d "${DUNE_OVERLAY_DIR}/zarith" ]; then
  echo "Installing dune overlay for zarith..."
  cp "${DUNE_OVERLAY_DIR}/zarith/dune" "${VENDOR_DIR}/zarith/dune"
  cp "${DUNE_OVERLAY_DIR}/zarith/dune-project" "${VENDOR_DIR}/zarith/dune-project"
fi

echo "Done.  To build:"
echo "  1. cd vendor/rocq && make dunestrap"
echo "  2. dune build vendor/rocq/topbin/coqc_bin.exe --profile release"
echo ""
echo "Note: rocq's theories/dune must be generated via 'make dunestrap'"
echo "before the full dune build will succeed."
