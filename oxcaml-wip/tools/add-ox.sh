#!/usr/bin/env bash
# add-ox.sh DUNIVERSE_PKG OPAM_PKG_VERSION
# Put the oxcaml/opam-repository version of a package into DUNIVERSE_PKG/ox,
# gate both copies on %{ocaml_version}, and merge package declarations.
set -euo pipefail
# Env: DU duniverse dir; T scratch dir (sources, backups); S dir holding an
# oxcaml/opam-repository clone as $S/ox-opam (only for the opam form).
: "${DU:?}" "${T:?}"; S=${S:-$T}
G=$(cd "$(dirname "$0")" && pwd)
pkgdir=$1; ov=$2                       # e.g. ppxlib ppxlib.0.33.0+ox2, or a local dir
dst=$DU/$pkgdir

[ -d "$T/backup/$pkgdir" ] || { mkdir -p "$T/backup"; cp -a "$dst" "$T/backup/$pkgdir"; }
if [ -d "$ov" ]; then
  srcdir=$ov
else
name=${ov%%.*}
opam=$S/ox-opam/packages/$name/$ov/opam
srcdir=$T/src/$ov
rm -rf "$srcdir"; mkdir -p "$srcdir"
url=$(sed -n '/^url {/,/^}/p' "$opam" | grep -oE 'https?://[^"]+' | head -1)
curl -sfL "$url" -o "$T/src/$ov.tgz"
tar xzf "$T/src/$ov.tgz" -C "$T/src/$ov" --strip-components=1
for p in $(sed -n '/^patches:/,/^\]/p' "$opam" | grep -oE '"[^"]+"' | tr -d '"'); do
  patch -d "$T/src/$ov" -p1 -s < "$(dirname "$opam")/files/$p"
done
fi
rm -rf "$dst/ox"
cp -aL "$srcdir" "$dst/ox"
( cd "$dst/ox"; rm -rf test tests bench examples doc dev old_rtd_doc *.opam dune-workspace* )
# Package declarations from the copy that the stock project lacks.
for p in $(grep -oE '^\(package[[:space:]]*$|\(name [^)]+\)' "$dst/ox/dune-project" | grep -oE '\(name [^)]+' | sed 's/(name //' | tail -n +2); do
  grep -qE "\(name $p\)" "$dst/dune-project" || printf '\n(package (name %s))\n' "$p" >> "$dst/dune-project"
done
# Package names can also only exist as .opam files.
for f in "$srcdir"/*.opam; do
  p=$(basename "$f" .opam)
  grep -qE "\(name $p\)" "$dst/dune-project" || [ -f "$dst/$p.opam" ] || cp "$f" "$dst/$p.opam"
done
ol=$(sed -n '1s/(lang dune \(.*\))/\1/p' "$dst/ox/dune-project"); pl=$(sed -n '1s/(lang dune \(.*\))/\1/p' "$dst/dune-project")
[ "$(printf '%s\n%s\n' "$ol" "$pl" | sort -V | tail -1)" = "$pl" ] || sed -i "1s/.*/(lang dune $ol)/" "$dst/dune-project"
pl=$(sed -n "1s/(lang dune \\(.*\\))/\\1/p" "$dst/dune-project"); [ "$(printf "%s\\n3.0\\n" "$pl" | sort -V | tail -1)" = "$pl" ] || sed -i "1s/.*/(lang dune 3.0)/" "$dst/dune-project"
rm -f "$dst/ox/dune-project"
python3 "$G/gate.py" "$dst/ox" ox
python3 "$G/gate.py" "$dst" stock --skip ox
