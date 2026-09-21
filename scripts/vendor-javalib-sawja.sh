#!/usr/bin/env bash
# Build javalib + sawja (non-dune, not in the opam-monorepo lock) into a
# per-runtime prefix, opam-free; benchmarks/infer/infer.build.sh points
# OCAMLPATH at it. camlzip here only builds javalib: infer links the duniverse
# copy (same 1.11 source, so .cmi hashes match).
# Env: JS_PREFIX (required) per-runtime prefix dir; JS_SRC clone dir.
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${JS_SRC:-$(pwd)/vendor-javalib-sawja-src}"
PREFIX="${JS_PREFIX:?set JS_PREFIX to the per-runtime prefix dir}"

source "${MONOREPO_DIR}/scripts/lib-sources.sh"

# The Makefiles are GNU-flavoured; FreeBSD bmake fails with
#   make: camlzip/Makefile:26: Cannot open /Makefile.config
MAKE="$(gnu_make)"

mkdir -p "$SRC"
clone_pinned cppo    "$SRC/cppo"
clone_pinned extlib  "$SRC/extlib"
clone_pinned camlzip "$SRC/camlzip"
clone_pinned javalib "$SRC/javalib"
clone_pinned sawja   "$SRC/sawja"

rm -rf "$PREFIX"; mkdir -p "$PREFIX/lib/stublibs" "$PREFIX/bin"
# Drop build artifacts left by another compiler.
for d in cppo extlib camlzip javalib sawja; do
  git -C "$SRC/$d" clean -fdxq && git -C "$SRC/$d" checkout -q .
done
export OCAMLPATH="$PREFIX/lib" OCAMLFIND_DESTDIR="$PREFIX/lib" PATH="$PREFIX/bin:$PATH"
mkdir -p "$OCAMLFIND_DESTDIR"
echo "compiler: $(ocaml -version)"

# extlib's dune build preprocesses with cppo; build it into PREFIX/bin rather
# than requiring it in every runtime switch.
echo "[0/4] cppo (dune build -> PREFIX/bin, so extlib's build can find it)"
dune build --root "$SRC/cppo" --profile release src/cppo_main.exe
install -m755 "$SRC/cppo/_build/default/src/cppo_main.exe" "$PREFIX/bin/cppo"
command -v cppo >/dev/null 2>&1 || { echo "ERROR: cppo build did not land on PATH" >&2; exit 1; }

echo "[1/4] extlib (dune build @install)"
# --root keeps dune from adopting the enclosing macro-benches workspace.
dune build --root "$SRC/extlib" --profile release @install
dune install --root "$SRC/extlib" --prefix "$PREFIX" --libdir "$PREFIX/lib" extlib

echo "[2/4] camlzip (make; findlib install -> PREFIX)"
( cd "$SRC/camlzip"
  "$MAKE" all
  "$MAKE" allopt
  "$MAKE" install )
echo "      $(ocamlfind query zip 2>&1) / $(ocamlfind query camlzip 2>&1)"

echo "[3/4] javalib (configure.sh -l PREFIX + make; needs extlib + camlzip)"
# -l sets OCAMLFIND_DESTDIR + OCAMLPATH to the prefix; without it `make install`
# fails with "Package javalib is already installed" against the switch.
( cd "$SRC/javalib"
  ./configure.sh -l "$PREFIX/lib"
  "$MAKE"
  "$MAKE" install )
echo "      $(ocamlfind query javalib 2>&1)"

echo "[4/4] sawja (configure.sh -l PREFIX + make; needs javalib)"
( cd "$SRC/sawja"
  ./configure.sh -l "$PREFIX/lib"
  "$MAKE"
  "$MAKE" install )
echo "      $(ocamlfind query sawja 2>&1)"
echo "PREFIX READY: $PREFIX"

# Self-test: link sawja from PREFIX only.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo '(lang dune 3.0)'                            > "$T/dune-project"
echo '(executable (name t) (libraries sawja))'   > "$T/dune"
echo 'let () = print_string "JAVALIB-SAWJA-PREFIX-OK\n"' > "$T/t.ml"
( cd "$T" && env OCAMLPATH="$PREFIX/lib" dune build ./t.exe \
  && CAML_LD_LIBRARY_PATH="$PREFIX/lib/stublibs" ./_build/default/t.exe )
