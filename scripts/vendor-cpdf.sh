#!/usr/bin/env bash
# vendor-cpdf.sh — download and extract camlpdf + cpdf-source into vendor/.
#
# cpdf uses OCamlMakefile (not dune), so we also install hand-written dune
# files that let the monorepo build everything with `dune build`.
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
DUNE_OVERLAY_DIR="${MONOREPO_DIR}/dune-overlays"

# --- camlpdf (PDF library, dependency of cpdf) ---
CAMLPDF_VERSION="2.8.1"
CAMLPDF_URL="https://github.com/johnwhitington/camlpdf/archive/refs/tags/v${CAMLPDF_VERSION}.tar.gz"
CAMLPDF_MD5="93883956f317d4037341b6a0da8a6d03"

# --- cpdf-source (PDF command-line tool) ---
CPDF_VERSION="2.8.1"
CPDF_URL="https://github.com/johnwhitington/cpdf-source/archive/refs/tags/v${CPDF_VERSION}.tar.gz"
CPDF_MD5="45ba51aae6b5d3ea6cb421037f8f73bb"

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

# ---- download ----
download_and_extract "camlpdf" "${CAMLPDF_URL}" "${CAMLPDF_MD5}" "${VENDOR_DIR}/camlpdf"
download_and_extract "cpdf-source" "${CPDF_URL}" "${CPDF_MD5}" "${VENDOR_DIR}/cpdf-source"

# ---- install dune overlays ----
# camlpdf and cpdf use OCamlMakefile, not dune.  Copy hand-written dune
# files so they build inside the monorepo workspace.
if [ -d "${DUNE_OVERLAY_DIR}/camlpdf" ]; then
  echo "Installing dune overlay for camlpdf..."
  cp "${DUNE_OVERLAY_DIR}/camlpdf/dune" "${VENDOR_DIR}/camlpdf/dune"
  cp "${DUNE_OVERLAY_DIR}/camlpdf/dune-project" "${VENDOR_DIR}/camlpdf/dune-project"
fi

if [ -d "${DUNE_OVERLAY_DIR}/cpdf-source" ]; then
  echo "Installing dune overlay for cpdf-source..."
  cp "${DUNE_OVERLAY_DIR}/cpdf-source/dune" "${VENDOR_DIR}/cpdf-source/dune"
  cp "${DUNE_OVERLAY_DIR}/cpdf-source/dune-project" "${VENDOR_DIR}/cpdf-source/dune-project"
fi

echo "Done.  Build with:"
echo "  dune build vendor/cpdf-source/cpdf.exe --profile release"
