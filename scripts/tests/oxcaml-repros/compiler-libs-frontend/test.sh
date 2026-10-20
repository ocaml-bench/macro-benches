# Links against compiler-libs.common only (orig), or compiler-libs.bytecomp's
# archives as findlib resolves them (fixed): OxCaml moved Printtyp into
# ocamlfrontend.cmxa, which bytecomp requires there.
bin=$1 v=$2 libs=ocamlcommon.cmxa
if [ "$v" = fixed ]; then
  [ -f "$("$bin/ocamlopt" -where)/compiler-libs/ocamlfrontend.cmxa" ] && libs="$libs ocamlfrontend.cmxa"
  libs="$libs ocamlbytecomp.cmxa"
fi
"$bin/ocamlopt" -I +compiler-libs $libs m.ml -o m.exe
