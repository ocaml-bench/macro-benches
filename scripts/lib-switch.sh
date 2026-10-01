#!/usr/bin/env bash
# The opam switch setup-monorepo.sh and ppx-expand.sh run on, created on first
# use. Pinned because the ppx expansion is only reproducible on exactly these
# versions, and so every machine runs setup in the same environment. Callers
# never change the active switch: they read this one's environment in their
# own process.
TOOLS_SWITCH="${TOOLS_SWITCH:-macro-benches-tools}"
TOOLS_PACKAGES="ocaml-base-compiler.5.4.1 dune.3.22.1 ocamlfind.1.9.8 opam-monorepo.0.4.3 zarith.1.14"

# ensure_tools_switch <opam>: create the switch, or install what it lacks. A
# package at another version is an error, not an upgrade: the switch may be
# someone's own.
ensure_tools_switch() {
  local opam="$1" pkg installed have missing=""
  if ! "$opam" switch list --short 2>/dev/null | grep -qx "$TOOLS_SWITCH"; then
    echo "Creating opam switch $TOOLS_SWITCH ($TOOLS_PACKAGES)..."
    "$opam" switch create "$TOOLS_SWITCH" --no-switch --yes --packages="${TOOLS_PACKAGES// /,}"
  fi
  installed="$("$opam" list --switch="$TOOLS_SWITCH" --installed --short --columns=package 2>/dev/null)"
  for pkg in $TOOLS_PACKAGES; do
    have="$(grep "^${pkg%%.*}\." <<< "$installed" || true)"
    if [ -z "$have" ]; then
      missing="$missing $pkg"
    elif [ "$have" != "$pkg" ]; then
      echo "ERROR: opam switch $TOOLS_SWITCH has $have; setup needs $pkg." >&2
      echo "       Remove that switch, or set TOOLS_SWITCH to a new name." >&2
      return 1
    fi
  done
  if [ -n "$missing" ]; then
    # shellcheck disable=SC2086
    "$opam" install --switch="$TOOLS_SWITCH" --yes $missing
  fi
}
