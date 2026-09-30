#!/usr/bin/env bash
# Minimal reproducers for the OxCaml incompatibilities setup-oxcaml.sh works
# around. Each case in oxcaml-repros/ has an original (the shape found in a
# vendored package) and the fixed shape the patch uses. Expected: both compile on
# stock OCaml; on OxCaml the original fails and the fixed one compiles.
#
# Usage: bash scripts/tests/oxcaml-repros.sh [<bin dir>...]
#   default: the ocamlopt on PATH. Pass one bin dir per compiler to compare.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/oxcaml-repros" && pwd)"
[ $# -gt 0 ] || set -- "$(dirname "$(command -v ocamlopt)")"

# compile <bin> <dir> <variant>: 0 when the variant compiles.
compile() {
  local bin=$1 dir=$2 v=$3 t
  t="$(mktemp -d)"
  if [ -f "$dir/m.mli" ]; then
    cp "$dir/m.mli" "$t/m.mli" && cp "$dir/$v.ml" "$t/m.ml"
    ( cd "$t" && "$bin/ocamlopt" -alert -deprecated -c m.mli && "$bin/ocamlopt" -alert -deprecated -c m.ml ) >"$t/log" 2>&1
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
    printf '  %-22s' "$(basename "$dir")"
    compile "$bin" "$dir" orig 2>/dev/null && o=ok || o=FAILS
    compile "$bin" "$dir" fixed 2>/dev/null && f=ok || { f=FAILS; status=1; }
    printf 'original: %-6s fixed: %s\n' "$o" "$f"
  done
done
exit $status
