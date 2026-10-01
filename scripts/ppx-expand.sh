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
#   --update  record this expansion in the manifest instead of checking it
#             (after a bump; once per OS for the paths in scripts/ppx-expand/per-os)
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
MANIFEST=scripts/ppx-expand/manifest
PER_OS=scripts/ppx-expand/per-os
OS="$(uname -s)"
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

# This OS's entries of a manifest: "hash  path", sorted. A path in per-os has
# one line per OS, with the OS (uname -s) as a third column.
manifest_view() {
  awk -v os="$OS" '!/^#/ && NF && (NF == 2 || $3 == os) { print $1 "  " $2 }' "$1" | LC_ALL=C sort
}

# Record the marker in the manifest, keeping the other OSes' lines.
update_manifest() {
  [ -f "$MANIFEST" ] || : > "$MANIFEST"
  {
    echo "# BLAKE2b-256 of every file scripts/ppx-expand.sh writes (dashes: deleted)."
    echo "# A third column is the OS (uname -s) a line is for: paths in per-os."
    echo "# Regenerate with: bash scripts/ppx-expand.sh --update"
    awk -v os="$OS" '
      FILENAME == ARGV[1] { if (!/^#/ && NF) per[$1] = 1; next }
      FILENAME == ARGV[2] { if (!/^#/ && NF == 3 && $3 != os) print; next }
      !/^#/ && NF { if ($2 in per) print $1 "  " $2 "  " os; else print $1 "  " $2 }
    ' "$PER_OS" "$MANIFEST" "$MARKER" | LC_ALL=C sort -k2,2 -k3,3
  } > "$MANIFEST.tmp"
  mv "$MANIFEST.tmp" "$MANIFEST"
  echo "ppx-expand: recorded the expansion in $MANIFEST ($OS)."
}

check_manifest() {
  local want have
  want="$(manifest_view "$MANIFEST")"
  have="$(manifest_view "$MARKER")"
  if [ "$want" = "$have" ]; then
    echo "ppx-expand: the expansion matches $MANIFEST."
    return 0
  fi
  diff <(echo "$want") <(echo "$have") | awk '/^[<>]/ { print "  differs: " $3 }' | LC_ALL=C sort -u | head -50 >&2
  echo "ERROR: the expansion differs from $MANIFEST. After a bump, run with --update;" >&2
  echo "       a path in per-os needs an --update on each OS." >&2
  return 1
}

if [[ -x /usr/local/bin/opam ]]; then
  _OPAM=/usr/local/bin/opam
else
  _OPAM="$(command -v opam || true)"
fi
[ -n "${_OPAM:-}" ] || { echo "ERROR: opam not found." >&2; exit 1; }

# Already expanded (e.g. a restored CI cache): only check it is the expansion
# the manifest describes, which needs no switch.
if [ -f "$MARKER" ]; then
  if [ "$UPDATE" = 1 ]; then update_manifest; else check_manifest; fi
  exit
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

  mkdir -p "$TOOL_DIR"
  cp scripts/ppx-expand/ppx_expand.ml "$TOOL_DIR/"
  (cd "$TOOL_DIR" && \
     ocamlopt -I +compiler-libs -I +str ocamlcommon.cmxa str.cmxa ppx_expand.ml -o ppx_expand)

  # In-repo ppx-src/ sources first: the build compiles their expansion.
  "$TOOL_DIR/ppx_expand" --build-dir "$BUILD_DIR" --ppx-src-only

  # The build scripts set up what each benchmark needs (goblint's apron,
  # infer's javalib), so a real build preprocesses exactly what benchmark
  # builds do. Its outputs are not benchmark binaries: remove them.
  # From an empty build dir: every ppx output found must come from this build.
  echo "Building every benchmark on $TOOLS_SWITCH to find the ppx outputs..."
  rm -rf "$BUILD_DIR"
  if ! env -u GITHUB_STEP_SUMMARY RUNNING_OCAML_RUNTIME_NAME="$TAG" \
       RUNNING_OCAML_SWITCH="$TOOLS_SWITCH" LOG_DIR="$MONOREPO_DIR/ci-logs/$TAG" \
       bash scripts/ci-build-all.sh; then
    echo "ERROR: a benchmark failed to build on $TOOLS_SWITCH; see ci-logs/$TAG/." >&2
    exit 1
  fi
  find benchmarks -type f -name "*-$TAG*" -delete

  "$TOOL_DIR/ppx_expand" --build-dir "$BUILD_DIR"
)
if [ "$UPDATE" = 1 ]; then update_manifest; else check_manifest; fi
