#!/usr/bin/env bash
# Build PCRE 1 (devkit's regex library, through pcre-ocaml) from pinned source
# into vendor/.pcre-prefix, so no system package is needed: distros are dropping
# it (Ubuntu 26.04 has no libpcre3-dev, Homebrew deprecated pcre). Static only,
# so the benchmarks link it in. lib-portable.sh puts its pkgconfig dir first on
# PKG_CONFIG_PATH, which is where pcre-ocaml's discover looks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${ROOT}/vendor/.pcre-prefix"
source "${ROOT}/scripts/lib-sources.sh"

VERSION="$(src_field pcre version)"
if grep -qx "Version: ${VERSION}" "${PREFIX}/lib/pkgconfig/libpcre.pc" 2>/dev/null; then
  echo "  PCRE ${VERSION} already built in ${PREFIX}. Skipping."
  exit 0
fi

MAKE="$(gnu_make)"
_tmp="$(mktemp -d)"
trap 'rm -rf "${_tmp}"' EXIT
curl -fsSL --retry 3 --retry-all-errors --retry-delay 5 -o "${_tmp}/pcre.tar.bz2" "$(src_field pcre url)"
echo "$(src_field pcre sha256)  ${_tmp}/pcre.tar.bz2" | shasum -a 256 -c - >/dev/null \
  || { echo "ERROR: checksum mismatch for the PCRE ${VERSION} tarball" >&2; exit 1; }
tar --no-same-owner -xjf "${_tmp}/pcre.tar.bz2" -C "${_tmp}"

# UTF-8 and Unicode properties: devkit's Stre compiles [^\pL\pN.]+ with `UTF8 at
# module initialisation. PIC: pcre-ocaml also links it into a shared stub library.
rm -rf "${PREFIX}"
if ! ( cd "${_tmp}/pcre-${VERSION}"
       ./configure --prefix="${PREFIX}" --disable-shared --enable-static --with-pic \
         --enable-utf8 --enable-unicode-properties --disable-cpp
       "${MAKE}" -j"$(ncpu)" && "${MAKE}" install ) > "${_tmp}/build.log" 2>&1; then
  echo "ERROR: PCRE ${VERSION} build failed (devkit needs it)." >&2
  echo "---- last 25 lines of its output ----" >&2
  tail -25 "${_tmp}/build.log" >&2
  exit 1
fi
echo "  PCRE ${VERSION} built into ${PREFIX}"
