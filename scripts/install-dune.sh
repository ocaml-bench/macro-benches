#!/usr/bin/env bash
# Dowloads the release binary where one exists, else built in
# a stock switch (e.g., FreeBSD, where dune ships no binary).
#
# Usage: bash scripts/install-dune.sh <dir>
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$MONOREPO_DIR/.github/dune-pin.env"
source "$MONOREPO_DIR/scripts/lib-switch.sh"
dest="$1"
mkdir -p "$dest"

case "$(uname -s) $(uname -m)" in
  "Linux x86_64") target=x86_64-unknown-linux-musl ;;
  "Darwin arm64") target=aarch64-apple-darwin ;;
  *) target="" ;;
esac

if [ -n "$target" ]; then
  sha_var="DUNE_SHA256_${target//-/_}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 --retry-all-errors -o "$tmp/dune.tar.gz" \
    "https://get.dune.build/${DUNE_VERSION}/${target}/dune-${DUNE_VERSION}-${target}.tar.gz"
  if command -v sha256sum >/dev/null; then
    got="$(sha256sum "$tmp/dune.tar.gz" | cut -d' ' -f1)"
  else
    got="$(shasum -a 256 "$tmp/dune.tar.gz" | cut -d' ' -f1)"
  fi
  if [ "$got" != "${!sha_var}" ]; then
    echo "ERROR: dune ${DUNE_VERSION} for ${target} has sha256 ${got}, expected ${!sha_var}." >&2
    exit 1
  fi
  tar -xzf "$tmp/dune.tar.gz" -C "$tmp"
  cp -f "$tmp/dune-${DUNE_VERSION}-${target}/dune" "$dest/dune"
else
  switch="dune-${DUNE_VERSION}"
  if ! opam switch list --short | grep -qx "$switch"; then
    opam switch create "$switch" --no-switch --yes --repos=default \
      --packages="ocaml-base-compiler.${TOOLS_OCAML_VERSION},dune.${DUNE_VERSION}"
  fi
  cp -f "$(opam var bin --switch="$switch")/dune" "$dest/dune"
fi

if [ "$("$dest/dune" --version)" != "$DUNE_VERSION" ]; then
  echo "ERROR: $dest/dune is not dune ${DUNE_VERSION}." >&2
  exit 1
fi
echo "dune ${DUNE_VERSION} at $dest/dune"
