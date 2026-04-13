#!/usr/bin/env bash
# vendor-alt-ergo.sh — download and extract alt-ergo + dependencies into vendor/.
#
# Alt-ergo has many dependencies.  This script vendors the main source and
# all dune-compatible libraries.  Three deps (fmt, logs, camlzip) use
# topkg/make and need hand-written dune overlays; ppx_deriving pulls in
# the ppxlib ecosystem.
#
# System dependencies: libgmp-dev (for zarith), zlib1g-dev (for camlzip).
#
# Status: scaffolding.  Not all deps are fully integrated yet.  See README
# for details on what needs work.
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
DUNE_OVERLAY_DIR="${MONOREPO_DIR}/dune-overlays"

# ---- package definitions: name, version, url, md5 ----
# Alt-ergo itself
AE_VERSION="2.6.2"
AE_URL="https://github.com/OCamlPro/alt-ergo/archive/refs/tags/v${AE_VERSION}.tar.gz"
AE_MD5="e4b1ffc9541d75bee8e02a5e40b68cc0"

# Dolmen (SMT/TPTP/etc. parser + typechecker — core dep)
DOLMEN_VERSION="0.10"
DOLMEN_URL="https://github.com/Gbury/dolmen/archive/refs/tags/v${DOLMEN_VERSION}.tar.gz"
DOLMEN_MD5="a89db80202d2f2d0cd7ea73c46d5e5e1"

# ocplib-simplex (simplex solver — core dep)
OCPLIB_SIMPLEX_VERSION="0.5.1"
OCPLIB_SIMPLEX_URL="https://github.com/OCamlPro/ocplib-simplex/archive/refs/tags/v${OCPLIB_SIMPLEX_VERSION}.tar.gz"
OCPLIB_SIMPLEX_MD5="b6cb1e4852046a6aecfcfbbb94ecee51"

# psmt2-frontend (PSMT2 parser — parser dep)
PSMT2_VERSION="0.4.0"
PSMT2_URL="https://github.com/ACoquereau/psmt2-frontend/archive/refs/tags/${PSMT2_VERSION}.tar.gz"
PSMT2_MD5="4fc9f9a68343b4614f120c1556bee644"

# cmdliner (CLI parsing — uses dune)
CMDLINER_VERSION="1.3.0"
CMDLINER_URL="https://github.com/dbuenzli/cmdliner/archive/refs/tags/v${CMDLINER_VERSION}.tar.gz"
CMDLINER_MD5="49209ae417b18910eca24bd2ab6538da"

# ppx_blob (embed files as strings — PPX, uses dune)
PPX_BLOB_VERSION="0.9.0"
PPX_BLOB_URL="https://github.com/johnwhitington/ppx_blob/archive/refs/tags/${PPX_BLOB_VERSION}.tar.gz"
PPX_BLOB_MD5="8dc76254a66ed47aaab6e612ce5e913c"

# --- deps that need dune overlays (not yet integrated) ---
# camlzip  rel113  https://github.com/xavierleroy/camlzip  (Makefile, needs zlib)
# fmt      v0.9.0  https://github.com/dbuenzli/fmt         (topkg/ocamlbuild)
# logs     v0.7.0  https://github.com/dbuenzli/logs        (topkg/ocamlbuild)
#
# --- PPX ecosystem (not yet vendored) ---
# ppx_deriving v6.0.3 — depends on ppxlib, which pulls in sexplib0, base, etc.
# For now these must be installed in the opam switch.
#
# --- already vendored by vendor-coq.sh ---
# zarith 1.14 — shared with rocq; run vendor-coq.sh first or vendor it here.

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

# ---- download all ----
download_and_extract "alt-ergo"         "${AE_URL}"              "${AE_MD5}"              "${VENDOR_DIR}/alt-ergo"
download_and_extract "dolmen"           "${DOLMEN_URL}"          "${DOLMEN_MD5}"          "${VENDOR_DIR}/dolmen"
download_and_extract "ocplib-simplex"   "${OCPLIB_SIMPLEX_URL}"  "${OCPLIB_SIMPLEX_MD5}"  "${VENDOR_DIR}/ocplib-simplex"
download_and_extract "psmt2-frontend"   "${PSMT2_URL}"           "${PSMT2_MD5}"           "${VENDOR_DIR}/psmt2-frontend"
download_and_extract "cmdliner"         "${CMDLINER_URL}"        "${CMDLINER_MD5}"        "${VENDOR_DIR}/cmdliner"
download_and_extract "ppx_blob"         "${PPX_BLOB_URL}"        "${PPX_BLOB_MD5}"        "${VENDOR_DIR}/ppx_blob"

# zarith: check if already vendored (shared with coq)
if [ ! -d "${VENDOR_DIR}/zarith" ]; then
  echo ""
  echo "NOTE: zarith is not yet vendored.  Run vendor-coq.sh or add zarith"
  echo "vendoring to this script."
fi

echo ""
echo "Alt-ergo sources vendored.  Additional work needed before building:"
echo "  - Vendor remaining deps: fmt, logs, camlzip (need dune overlays)"
echo "  - Vendor PPX ecosystem: ppx_deriving + ppxlib (or install via opam)"
echo "  - Vendor zarith (or run vendor-coq.sh first)"
echo ""
echo "Once all deps are in place:"
echo "  dune build vendor/alt-ergo/src/bin/text/Main_text.exe --profile release"
