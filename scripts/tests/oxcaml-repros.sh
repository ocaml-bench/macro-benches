#!/usr/bin/env bash
# Minimal reproducers for the OxCaml incompatibilities setup-oxcaml.sh works
# around. Each case in oxcaml-repros/ has an original (the shape found in a
# vendored package) and the fixed shape the patch uses. Expected: both compile on
# stock OCaml; on OxCaml the original fails and the fixed one compiles.
#
# A case is orig.ml and fixed.ml, compiled against m.mli when there is one and
# with the flags in `flags`; fixed.oxcaml.ml replaces fixed.ml on OxCaml where no
# one source compiles on both (the variant files of setup-oxcaml.sh). A case with
# a test.sh runs `bash test.sh <bin dir> orig|fixed` in a copy of itself instead.
#
# Usage: bash scripts/tests/oxcaml-repros.sh [<bin dir>...]
#   default: the ocamlopt on PATH. Pass one bin dir per compiler to compare.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/oxcaml-repros" && pwd)"
[ $# -gt 0 ] || set -- "$(dirname "$(command -v ocamlopt)")"

# compile <bin> <dir> <variant>: 0 when the variant compiles.
compile() {
  local bin=$1 dir=$2 v=$3 t src flags=""
  t="$(mktemp -d)"
  if [ -f "$dir/test.sh" ]; then
    cp "$dir"/* "$t/"
    ( cd "$t" && bash test.sh "$bin" "$v" ) >"$t/log" 2>&1
  elif [ -f "$dir/orig.ml" ]; then
    src="$dir/$v.ml"
    case "$("$bin/ocamlopt" -version)" in *+ox*) [ -f "$dir/$v.oxcaml.ml" ] && src="$dir/$v.oxcaml.ml" ;; esac
    [ -f "$dir/flags" ] && flags=$(cat "$dir/flags")
    cp "$src" "$t/m.ml"
    [ -f "$dir/m.mli" ] && cp "$dir/m.mli" "$t/m.mli"
    ( cd "$t" && { [ ! -f m.mli ] || "$bin/ocamlopt" -alert -deprecated $flags -c m.mli; } \
        && "$bin/ocamlopt" -alert -deprecated $flags -c m.ml ) >"$t/log" 2>&1
  else
    # for-pack-cmi: the interface is compiled without -for-pack in "orig" only.
    cp "$dir"/a.mli "$dir"/a.ml "$dir"/b.ml "$t/"
    local mli_flag=""; [ "$v" = fixed ] && mli_flag="-for-pack P"
    ( cd "$t" && "$bin/ocamlc" $mli_flag -c a.mli && "$bin/ocamlopt" -for-pack P -c a.ml \
        && "$bin/ocamlopt" -for-pack P -c b.ml ) >"$t/log" 2>&1
  fi
  local rc=$?
  [ $rc -eq 0 ] || sed -n '1,/^Error/p;/^Error/,+2p' "$t/log" | grep -m2 -E "^Error|^ " | head -2 | sed 's/^/      /' >&2
  rm -rf "$t"
  return $rc
}

status=0
for bin in "$@"; do
  echo "== $("$bin/ocamlopt" -version) ($bin)"
  for dir in "$HERE"/*/; do
    dir=${dir%/}
    printf '  %-24s' "$(basename "$dir")"
    compile "$bin" "$dir" orig 2>/dev/null && o=ok || o=FAILS
    compile "$bin" "$dir" fixed 2>/dev/null && f=ok || { f=FAILS; status=1; }
    printf 'original: %-6s fixed: %s\n' "$o" "$f"
  done
done
exit $status
