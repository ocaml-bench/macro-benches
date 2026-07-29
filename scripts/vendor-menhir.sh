#!/usr/bin/env bash
# vendor-menhir.sh — download and extract menhir sources into vendor/menhir/.
set -euo pipefail

# src_field — every version, URL and checksum below comes from sources.yml,
# which is the single source of truth for what this repo vendors.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib-sources.sh"

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
VERSION="$(src_field menhir version)"
URL="$(src_field menhir url)"
MD5="$(src_field menhir md5)"

DEST="${VENDOR_DIR}/menhir"

if [ -d "${DEST}" ]; then
  echo "vendor/menhir/ already exists. Remove it first to re-vendor."
  exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "Downloading menhir ${VERSION}..."
curl -fSL "${URL}" -o "${TMPDIR}/menhir.tar.gz"

# Verify checksum.
ACTUAL_MD5="$(md5sum "${TMPDIR}/menhir.tar.gz" | cut -d' ' -f1)"
if [ "${ACTUAL_MD5}" != "${MD5}" ]; then
  echo "MD5 mismatch: expected ${MD5}, got ${ACTUAL_MD5}" >&2
  exit 1
fi

echo "Extracting..."
tar xzf "${TMPDIR}/menhir.tar.gz" -C "${TMPDIR}"

# The tarball extracts to a directory like menhir-20260209-<hash>/ or archive-<hash>/.
EXTRACTED="$(find "${TMPDIR}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | head -1)"
if [ -z "${EXTRACTED}" ]; then
  echo "Failed to find extracted directory" >&2
  exit 1
fi

mkdir -p "${VENDOR_DIR}"
mv "${EXTRACTED}" "${DEST}"

echo "Vendored menhir ${VERSION} to vendor/menhir/"
