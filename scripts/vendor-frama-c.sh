#!/usr/bin/env bash
# Clone Frama-C into vendor/frama-c (kernel + EVA only).
#
# Frama-C 32.1 is not in opam, and the opam package's why3 dep caps ocaml < 5.5.
# why3 is only needed by the WP plugin (dune `optional`), so vendoring the
# source and skipping WP/GUI/apron lets the build resolve on OCaml >= 5.5.
set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib-sources.sh"

FRAMAC_TAG="$(src_field frama-c branch)"
FRAMAC_URL="$(src_field frama-c repo)"

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
FRAMAC_DIR="${VENDOR_DIR}/frama-c"

# The tree is trimmed below, so check the marker file rather than the pin alone.
if [ -d "${FRAMAC_DIR}" ] && [ -f "${FRAMAC_DIR}/dune-project" ] && \
   [ "$(cat "${FRAMAC_DIR}/.pinned-commit" 2>/dev/null)" = "$(src_field frama-c commit)" ]; then
  echo "vendor/frama-c/ already at the pinned commit. Skipping."
  exit 0
fi

echo "Cloning Frama-C ${FRAMAC_TAG} (pinned)..."
rm -rf "${FRAMAC_DIR}"
clone_pinned frama-c "${FRAMAC_DIR}"
# Drop .git: the trimming below would make the checkout look massively dirty.
src_field frama-c commit > "${FRAMAC_DIR}/.pinned-commit"
rm -rf "${FRAMAC_DIR}/.git"

# Never built; ivette (GUI) would need Node + Yarn.
rm -rf "${FRAMAC_DIR}/ivette" "${FRAMAC_DIR}/doc" "${FRAMAC_DIR}/tests"

# Each plugin has its own dune-project + *.opam, mostly 0-byte placeholders.
# dune needs them to resolve public_name stanzas, but opam-monorepo cannot
# parse an empty opam file (and would pull each package's deps, e.g. wp's
# why3). A minimal dependency-free stanza satisfies both.
while IFS= read -r f; do
  printf 'opam-version: "2.0"\n' > "$f"
done < <(find "${FRAMAC_DIR}" -name '*.opam' -empty)

echo "Done.  Frama-C ${FRAMAC_TAG} vendored to vendor/frama-c/"
echo "  (kernel + EVA only; WP/why3, GUI, apron are optional and skipped)"
