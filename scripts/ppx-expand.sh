#!/usr/bin/env bash
# Replace ppx preprocessing with its expanded source, so benchmark builds never
# build a ppx. On a dedicated pinned switch, build every benchmark once, then
# expand every ppx output of that build in place (except the ppxs' own code)
# and check the result against scripts/ppx-expand/manifest.
#
# A benchmark's own source that uses a ppx lives in benchmarks/<tool>/ppx-src/;
# its expansion is committed one level up.
#
# Usage: bash scripts/ppx-expand.sh [--update]
#   --update  rewrite the manifest instead of checking against it (after a bump)
# Env:   PPX_SWITCH (default macro-benches-ppx): the dedicated switch, created
#        if missing. The caller's current switch is not changed.
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MONOREPO_DIR"

# The expansion is only reproducible if these are fixed.
PPX_OCAML=5.4.1
PPX_DUNE=3.22.1
PPX_OCAMLFIND=1.9.8
PPX_SWITCH="${PPX_SWITCH:-macro-benches-ppx}"
TAG=ppx-expand
BUILD_DIR="_build-$TAG"
TOOL_DIR=_build-ppx-expand-tool
MARKER=duniverse/.ppx-expanded

if [[ -x /usr/local/bin/opam ]]; then
  _OPAM=/usr/local/bin/opam
else
  _OPAM="$(command -v opam || true)"
fi
[ -n "${_OPAM:-}" ] || { echo "ERROR: opam not found." >&2; exit 1; }

# Already expanded (e.g. a restored CI cache): only check it is the expansion
# the manifest describes, which needs no switch.
if [ -f "$MARKER" ]; then
  if [ "${1:-}" = "--update" ]; then
    cp "$MARKER" scripts/ppx-expand/manifest
    echo "ppx-expand: tree already expanded; copied its manifest."
  elif cmp -s "$MARKER" scripts/ppx-expand/manifest; then
    echo "ppx-expand: tree already expanded and matches the manifest."
  else
    echo "ERROR: duniverse/ was expanded for a different manifest; re-run setup from a fresh duniverse/ and vendor/." >&2
    exit 1
  fi
  exit 0
fi

PACKAGES="ocaml-base-compiler.$PPX_OCAML dune.$PPX_DUNE ocamlfind.$PPX_OCAMLFIND"
if ! "$_OPAM" switch list --short 2>/dev/null | grep -qx "$PPX_SWITCH"; then
  echo "Creating opam switch $PPX_SWITCH ($PACKAGES)..."
  "$_OPAM" switch create "$PPX_SWITCH" --no-switch --yes --packages="${PACKAGES// /,}"
else
  # shellcheck disable=SC2086
  "$_OPAM" install --switch="$PPX_SWITCH" --yes $PACKAGES >/dev/null
fi

# jsoo's ppx_optcomp_light reads the compiler version from Sys.ocaml_version;
# let the per-version expansion override it. Idempotent.
PREDICATE=duniverse/js_of_ocaml/compiler/ppx-light-predicate/predicate.ml
if [ -f "$PREDICATE" ] && ! grep -q PPX_EXPAND_OCAML_VERSION "$PREDICATE"; then
  python3 - "$PREDICATE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "  let current = split Sys.ocaml_version\n"
new = ("  let current =\n"
       "    split\n"
       "      (match Sys.getenv_opt \"PPX_EXPAND_OCAML_VERSION\" with\n"
       "      | Some v -> v\n"
       "      | None -> Sys.ocaml_version)\n")
assert old in s, f"{p}: version lookup not found -- patch me"
open(p, "w").write(s.replace(old, new, 1))
PY
fi

(
  # Only the dedicated switch: another switch's bin/ on PATH (dune would use
  # its ocamlfind) or its OCAMLPATH would let its libraries into the build.
  unset OCAMLPATH CAML_LD_LIBRARY_PATH OCAMLLIB OCAMLTOP_INCLUDE_PATH OCAMLFIND_CONF
  root="$("$_OPAM" var root)"
  path=
  IFS=: read -ra entries <<< "$PATH"
  for e in "${entries[@]}"; do
    case "$e" in "$root"/*|*/_opam/bin) continue ;; esac
    path="${path:+$path:}$e"
  done
  export PATH="$path"
  eval "$("$_OPAM" env --switch="$PPX_SWITCH" --set-switch)"
  prefix="$("$_OPAM" var prefix --switch="$PPX_SWITCH")"
  for tool in ocamlc dune ocamlfind; do
    [ "$(command -v "$tool")" = "$prefix/bin/$tool" ] \
      || { echo "ERROR: $tool is not $PPX_SWITCH's ($(command -v "$tool"))." >&2; exit 1; }
  done
  [ "$(ocamlc -version)" = "$PPX_OCAML" ] && [ "$(dune --version)" = "$PPX_DUNE" ] \
    || { echo "ERROR: $PPX_SWITCH must have OCaml $PPX_OCAML and dune $PPX_DUNE" \
              "(has $(ocamlc -version), $(dune --version))." >&2; exit 1; }
  [ "$(ocamlc -config-var flambda)" = "false" ] \
    || { echo "ERROR: $PPX_SWITCH must not be an flambda switch." >&2; exit 1; }

  mkdir -p "$TOOL_DIR"
  cp scripts/ppx-expand/ppx_expand.ml "$TOOL_DIR/"
  (cd "$TOOL_DIR" && \
     ocamlopt -I +compiler-libs -I +str ocamlcommon.cmxa str.cmxa ppx_expand.ml -o ppx_expand)

  # In-repo ppx-src/ sources first: the build compiles their expansion.
  "$TOOL_DIR/ppx_expand" --build-dir "$BUILD_DIR" --ppx-src-only

  # The build scripts set up what each benchmark needs (goblint's apron,
  # infer's javalib), so a real build preprocesses exactly what benchmark
  # builds do. Its outputs are not benchmark binaries: remove them.
  echo "Building every benchmark on $PPX_SWITCH to find the ppx outputs..."
  if ! env -u GITHUB_STEP_SUMMARY RUNNING_OCAML_RUNTIME_NAME="$TAG" \
       RUNNING_OCAML_SWITCH="$PPX_SWITCH" LOG_DIR="$MONOREPO_DIR/ci-logs/$TAG" \
       bash scripts/ci-build-all.sh; then
    echo "ERROR: a benchmark failed to build on $PPX_SWITCH; see ci-logs/$TAG/." >&2
    exit 1
  fi
  find benchmarks -type f -name "*-$TAG*" -delete

  "$TOOL_DIR/ppx_expand" --build-dir "$BUILD_DIR" "$@"
)
