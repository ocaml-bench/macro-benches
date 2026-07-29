#!/usr/bin/env bash
# vendor-devkit-deps.sh — download and extract non-dune deps for devkit.
#
# These are thin OCaml C-binding wrappers.  Hand-written dune overlays
# in dune-overlays/ teach dune how to build them.
#
# System dependencies: libevent-dev, libcurl4-openssl-dev (or libcurl4-gnutls-dev)
set -euo pipefail

# src_field — every version, URL and checksum below comes from sources.yml,
# which is the single source of truth for what this repo vendors.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib-sources.sh"

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
DUNE_OVERLAY_DIR="${MONOREPO_DIR}/dune-overlays"

# --- libevent OCaml bindings ---
LIBEVENT_VERSION="$(src_field libevent version)"
LIBEVENT_URL="$(src_field libevent url)"
LIBEVENT_MD5="$(src_field libevent md5)"

# --- ocurl (OCaml bindings to libcurl) ---
OCURL_VERSION="$(src_field ocurl version)"
OCURL_URL="$(src_field ocurl url)"
OCURL_MD5="$(src_field ocurl md5)"

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

download_and_extract "libevent" "${LIBEVENT_URL}" "${LIBEVENT_MD5}" "${VENDOR_DIR}/libevent"
download_and_extract "ocurl" "${OCURL_URL}" "${OCURL_MD5}" "${VENDOR_DIR}/ocurl"

# Install dune overlays
for pkg in libevent ocurl; do
  if [ -d "${DUNE_OVERLAY_DIR}/${pkg}" ]; then
    echo "Installing dune overlay for ${pkg}..."
    cp "${DUNE_OVERLAY_DIR}/${pkg}/dune" "${VENDOR_DIR}/${pkg}/dune"
    cp "${DUNE_OVERLAY_DIR}/${pkg}/dune-project" "${VENDOR_DIR}/${pkg}/dune-project"
    # Copy config.h if present (needed by ocurl)
    [ -f "${DUNE_OVERLAY_DIR}/${pkg}/config.h" ] && \
      cp "${DUNE_OVERLAY_DIR}/${pkg}/config.h" "${VENDOR_DIR}/${pkg}/config.h"
  fi
done

echo "Done.  System deps needed: libevent-dev, libcurl4-openssl-dev"
