#!/usr/bin/env bash
# Rebuild the OxCaml two-copies experiment on a set-up tree (make setup done,
# vendor/infer present). OXSRC: OxCaml compiler checkout at be90cb46.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$ROOT/oxcaml-wip
OXSRC=${OXSRC:?OxCaml compiler checkout}
export DU=$ROOT/duniverse T=${T:-$(mktemp -d)}

# OxCaml copies (duniverse/<pkg>/ox), gated on %{ocaml_version}.
bash "$W/tools/add-ox.sh" ppxlib "$OXSRC/external/ppxlib"
bash "$W/tools/add-ox.sh" ppxlib_jane "$OXSRC/external/ppxlib_jane"
git clone -q https://github.com/patricoferris/ppx_deriving.git "$T/ppx_deriving-ox"
git -C "$T/ppx_deriving-ox" checkout -q 4cb09f54ff13e525804852190bfed8abb9267014
rm -rf "$T/ppx_deriving-ox/.git"
bash "$W/tools/add-ox.sh" ppx_deriving "$T/ppx_deriving-ox"

# New OxCaml-only package needed by OxCaml's ppxlib.
rm -rf "$DU/sexp_type"
git clone -q https://github.com/janestreet/sexp_type.git "$DU/sexp_type"
git -C "$DU/sexp_type" checkout -q 6d16004ed65cbed153c130d4beba1c5655146152
rm -rf "$DU/sexp_type/.git" "$DU/sexp_type/grammar_type" "$DU/sexp_type/test"
python3 "$W/tools/gate.py" "$DU/sexp_type" ox

# Per-file variants and portable fixes.
for p in "$W"/patches/*.patch; do patch -d "$ROOT" -p1 -s < "$p"; done
