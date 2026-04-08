#!/usr/bin/env bash
# vendor-menhir.sh — download and extract menhir sources into vendor/menhir/.
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
VERSION="20260209"
URL="https://gitlab.inria.fr/fpottier/menhir/-/archive/${VERSION}/archive.tar.gz"
MD5="e993231085db95ab011ffe0cd606d9dd"

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
