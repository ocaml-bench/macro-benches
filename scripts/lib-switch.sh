#!/usr/bin/env bash
# The opam switch setup-monorepo.sh and ppx-expand.sh run on, created on first
# use. Pinned because the ppx expansion is only reproducible on exactly these
# versions, and so every machine runs setup in the same environment. Callers
# never change the active switch: they read this one's environment in their
# own process.
TOOLS_SWITCH="${TOOLS_SWITCH:-macro-benches-tools}"
TOOLS_PACKAGES="ocaml-base-compiler.5.4.1 dune.3.22.1 ocamlfind.1.9.8 opam-monorepo.0.4.3 zarith.1.14"
TOOLS_OCAML_VERSION=5.4.1

# ensure_tools_switch <opam>: create the switch, or install what it lacks. A
# package at another version is an error, not an upgrade: the switch may be
# someone's own. Only opam's default repository is used, so another one
# registered globally (e.g. a relocatable-compiler repository, whose
# ocaml-base-compiler.5.4.1 is 5.4.1+relocatable) cannot supply the compiler.
ensure_tools_switch() {
  local opam="$1" pkg installed have missing=""
  if ! "$opam" switch list --short --color=never 2>/dev/null | grep -qx "$TOOLS_SWITCH"; then
    echo "Creating opam switch $TOOLS_SWITCH ($TOOLS_PACKAGES)..."
    "$opam" switch create "$TOOLS_SWITCH" --no-switch --yes --repos=default \
      --packages="${TOOLS_PACKAGES// /,}"
  fi
  installed="$("$opam" list --switch="$TOOLS_SWITCH" --installed --short --columns=package --color=never 2>/dev/null)"
  for pkg in $TOOLS_PACKAGES; do
    have="$(grep "^${pkg%%.*}\." <<< "$installed" || true)"
    if [ -z "$have" ] && [ "${pkg%%.*}" = ocaml-base-compiler ]; then
      echo "ERROR: opam switch $TOOLS_SWITCH does not use $pkg; setup will not change its compiler." >&2
      echo "       Set TOOLS_SWITCH to a new name, and setup creates it." >&2
      return 1
    elif [ -z "$have" ]; then
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
  # The package versions are not enough: the compiler itself must be the plain one.
  local version flambda
  version="$("$opam" exec --switch="$TOOLS_SWITCH" -- ocamlc -version)"
  flambda="$("$opam" exec --switch="$TOOLS_SWITCH" -- ocamlc -config-var flambda)"
  if [ "$version" != "$TOOLS_OCAML_VERSION" ] || [ "$flambda" != "false" ]; then
    echo "ERROR: opam switch $TOOLS_SWITCH has OCaml $version (flambda: $flambda);" >&2
    echo "       setup needs plain $TOOLS_OCAML_VERSION from opam's default repository." >&2
    echo "       Remove that switch, or set TOOLS_SWITCH to a new name." >&2
    return 1
  fi
}
