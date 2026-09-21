#!/usr/bin/env bash
# GC/RSS fingerprint probe: runs a benchmark binary under OCAMLRUNPARAM=v=0x400
# and /usr/bin/time -v, emits one CSV row. Sweep input sizes to see whether the
# GC shape changes or just scales.
#
# Usage:   scripts/fingerprint.sh <label> <exe> [args...]
# Header:  scripts/fingerprint.sh --header
set -uo pipefail

if [[ "${1:-}" == "--header" ]]; then
  echo "label,wall_s,user_s,sys_s,max_rss_kb,minor_colls,major_colls,forced_major,minor_words,promoted_words,major_words,allocated_words,top_heap_words,heap_words,promo_frac"
  exit 0
fi

label="${1:?label required}"; shift
exe="${1:?exe required}"; shift

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

/usr/bin/time -v env OCAMLRUNPARAM="v=0x400" "$exe" "$@" >/dev/null 2>"$tmp"

get() { grep -iE "$1" "$tmp" | head -1 | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1; }
# time -v prints wall clock as h:mm:ss or m:ss
wall_raw="$(grep -i 'wall clock' "$tmp" | grep -oE '[0-9:.]+' | tail -1)"
wall_s="$(awk -F: '{if(NF==3)print $1*3600+$2*60+$3; else if(NF==2)print $1*60+$2; else print $1}' <<<"$wall_raw")"

user_s="$(get 'User time')"
sys_s="$(get 'System time')"
rss="$(get 'Maximum resident set size')"
minc="$(get 'minor_collections')"
majc="$(get 'major_collections')"
fmaj="$(get 'forced_major_collections')"
minw="$(get 'minor_words')"
prow="$(get 'promoted_words')"
majw="$(get 'major_words')"
allw="$(get 'allocated_words')"
toph="$(get 'top_heap_words')"
heap="$(get 'heap_words')"
promo="$(awk -v p="${prow:-0}" -v m="${minw:-0}" 'BEGIN{if(m>0)printf "%.4f",p/m; else print "NA"}')"

echo "${label},${wall_s},${user_s},${sys_s},${rss},${minc},${majc},${fmaj},${minw},${prow},${majw},${allw},${toph},${heap},${promo}"
