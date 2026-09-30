#!/usr/bin/env bash
# variant.sh FILE PATCH [STRIP]
# Split FILE (foo.ml) into foo.upstream.ml + foo.oxcaml.ml (= upstream + PATCH)
# and add a rule to FILE's dune that picks one by %{ocaml_version}.
set -euo pipefail
f=$1; patch=$2; strip=${3:-1}
d=$(dirname "$f"); b=$(basename "$f"); stem=${b%.*}; ext=${b##*.}
up=$d/$stem.upstream.$ext; ox=$d/$stem.oxcaml.$ext
[ -f "$up" ] || mv "$f" "$up"
[ -f "$ox" ] || cp "$up" "$ox"
if [ "$patch" != - ]; then
# Apply only the hunks for this file.
python3 - "$patch" "$b" > "$d/.one.patch" <<'EOF'
import sys, re
text = open(sys.argv[1]).read(); name = sys.argv[2]
for chunk in re.split(r'(?m)^(?=diff |--- )', text):
    m = re.search(r'(?m)^\+\+\+ (\S+)', chunk)
    if m and m.group(1).endswith('/' + name):
        print(chunk[chunk.index('---'):] if '---' in chunk else chunk, end='')
EOF
patch -s "$ox" < "$d/.one.patch"; rm -f "$d/.one.patch" "$ox.orig"
fi
grep -q "$stem.oxcaml.$ext" "$d/dune" || cat >> "$d/dune" <<EOF

(rule
 (targets $b)
 (deps $stem.upstream.$ext $stem.oxcaml.$ext)
 (action
  (with-stdout-to
   %{targets}
   (system
    "case '%{ocaml_version}' in *+ox*) cat $stem.oxcaml.$ext ;; *) cat $stem.upstream.$ext ;; esac"))))
EOF
echo "variant: $f"
