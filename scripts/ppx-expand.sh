#!/usr/bin/env bash
# Replace ppx preprocessing with its expanded source, so benchmark builds never
# build a ppx. On the pinned tools switch, build every benchmark once, then
# expand every ppx output of that build in place (except the ppxs' own code)
# and check the result against scripts/ppx-expand/manifest.
#
# A benchmark's own source that uses a ppx lives in benchmarks/<tool>/ppx-src/;
# its expansion is committed one level up.
#
# Usage: bash scripts/ppx-expand.sh [--update]
#   --update  rewrite the manifest instead of checking against it (after a bump)
# Env:   TOOLS_SWITCH (default macro-benches-tools): see scripts/lib-switch.sh.
#        The caller's current switch is not changed.
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MONOREPO_DIR"

source scripts/lib-switch.sh
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

ensure_tools_switch "$_OPAM"

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
  eval "$("$_OPAM" env --switch="$TOOLS_SWITCH" --set-switch)"
  prefix="$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")"
  for tool in ocamlc dune ocamlfind; do
    [ "$(command -v "$tool")" = "$prefix/bin/$tool" ] \
      || { echo "ERROR: $tool is not $TOOLS_SWITCH's ($(command -v "$tool"))." >&2; exit 1; }
  done
  [ "$(ocamlc -config-var flambda)" = "false" ] \
    || { echo "ERROR: $TOOLS_SWITCH must not be an flambda switch." >&2; exit 1; }

  mkdir -p "$TOOL_DIR"
  cp scripts/ppx-expand/ppx_expand.ml "$TOOL_DIR/"
  (cd "$TOOL_DIR" && \
     ocamlopt -I +compiler-libs -I +str ocamlcommon.cmxa str.cmxa ppx_expand.ml -o ppx_expand)

  # In-repo ppx-src/ sources first: the build compiles their expansion.
  "$TOOL_DIR/ppx_expand" --build-dir "$BUILD_DIR" --ppx-src-only

  # The build scripts set up what each benchmark needs (goblint's apron,
  # infer's javalib), so a real build preprocesses exactly what benchmark
  # builds do. Its outputs are not benchmark binaries: remove them.
  echo "Building every benchmark on $TOOLS_SWITCH to find the ppx outputs..."
  if ! env -u GITHUB_STEP_SUMMARY RUNNING_OCAML_RUNTIME_NAME="$TAG" \
       RUNNING_OCAML_SWITCH="$TOOLS_SWITCH" LOG_DIR="$MONOREPO_DIR/ci-logs/$TAG" \
       bash scripts/ci-build-all.sh; then
    echo "ERROR: a benchmark failed to build on $TOOLS_SWITCH; see ci-logs/$TAG/." >&2
    exit 1
  fi
  find benchmarks -type f -name "*-$TAG*" -delete

  "$TOOL_DIR/ppx_expand" --build-dir "$BUILD_DIR" "$@"
)
