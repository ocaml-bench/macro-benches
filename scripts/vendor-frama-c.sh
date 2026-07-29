#!/usr/bin/env bash
# vendor-frama-c.sh — clone Frama-C source into vendor/frama-c.
#
# Frama-C 32.1 is not in the opam repository (it tops out at 32.0), and
# we only want a trimmed kernel+EVA build (no WP/why3, no GUI/apron), so
# we vendor the source manually — like pplacer — rather than locking the
# `frama-c` opam package.  The benchmark exe (benchmarks/frama-c/) links
# `frama-c.kernel` + `frama-c-eva.core` from this tree with -linkall and
# runs with -no-autoload-plugins, which bypasses dune-site plugin
# discovery entirely (the limitation that originally parked Frama-C).
#
# why3 is only used by src/plugins/wp (which is dune `(optional)` and so
# is skipped when why3 is absent); EVA's deps are just frama-c.kernel +
# frama-c-server.core, neither of which needs why3.  This is what lets
# the build resolve on OCaml >= 5.5 (the `frama-c` opam package's why3
# dep caps at ocaml < 5.5).
set -euo pipefail

# src_field — every version, URL and checksum below comes from sources.yml,
# which is the single source of truth for what this repo vendors.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib-sources.sh"

FRAMAC_TAG="$(src_field frama-c branch)"
FRAMAC_URL="$(src_field frama-c repo)"

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${MONOREPO_DIR}/vendor"
FRAMAC_DIR="${VENDOR_DIR}/frama-c"

# The tree is heavily trimmed below, so "already vendored" can't be decided from
# the pin alone: check for the marker file, and let clone_pinned decide the rest.
if [ -d "${FRAMAC_DIR}" ] && [ -f "${FRAMAC_DIR}/dune-project" ] && \
   [ "$(cat "${FRAMAC_DIR}/.pinned-commit" 2>/dev/null)" = "$(src_field frama-c commit)" ]; then
  echo "vendor/frama-c/ already at the pinned commit. Skipping."
  exit 0
fi

echo "Cloning Frama-C ${FRAMAC_TAG} (pinned)..."
rm -rf "${FRAMAC_DIR}"
clone_pinned frama-c "${FRAMAC_DIR}"
# Record the pin, then drop .git: the trimming below rewrites the tree, so a
# retained .git would report the checkout as massively dirty and tell us nothing.
src_field frama-c commit > "${FRAMAC_DIR}/.pinned-commit"
rm -rf "${FRAMAC_DIR}/.git"

# Strip dirs we never build, to cut tree size and avoid unrelated
# toolchain requirements:
#   - ivette/  : OCaml->JS GUI, requires Node v20/22 + Yarn at build time
#   - doc/     : manuals
#   - tests/   : the upstream test suite
rm -rf "${FRAMAC_DIR}/ivette" "${FRAMAC_DIR}/doc" "${FRAMAC_DIR}/tests"

# Frama-C is a multi-dune-project tree: every plugin/library has its own
# dune-project + *.opam (35 of the 37 are 0-byte dune-site placeholders).
# dune NEEDS these files present to resolve the (public_name ...) stanzas
# (e.g. frama-c.kernel, frama-c-eva.core) — deleting them breaks the
# build.  But opam-monorepo scans the whole tree and cannot parse a
# 0-byte opam file (and would also treat each as a local package, pulling
# their deps — e.g. wp's why3, which caps ocaml < 5.5).  Filling the
# empty ones with a minimal, dependency-free opam stanza satisfies both:
# dune sees the package declaration, opam-monorepo parses it and finds no
# deps to vendor (the real deps are declared in macro-bench-frama-c).
while IFS= read -r f; do
  printf 'opam-version: "2.0"\n' > "$f"
done < <(find "${FRAMAC_DIR}" -name '*.opam' -empty)

echo "Done.  Frama-C ${FRAMAC_TAG} vendored to vendor/frama-c/"
echo "  (kernel + EVA only; WP/why3, GUI, apron are optional and skipped)"
