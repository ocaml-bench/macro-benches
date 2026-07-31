#!/usr/bin/env bash
# vendor-javalib-sawja.sh — build javalib + sawja into a per-runtime prefix.
#
# javalib + sawja are non-dune (native configure.sh + Makefile) and are NOT in
# the opam-monorepo lock (see dune-project / macro-bench-infer.opam.template).
# Mirroring the apron chain (scripts/vendor-apron.sh + benchmarks/goblint), we
# build them per-runtime into a self-contained prefix using ONLY the active
# compiler + ocamlfind + make, and benchmarks/infer/infer.build.sh points
# OCAMLPATH at that prefix so infer links our javalib/sawja/extlib.  zip
# (camlzip) comes from the in-tree duniverse (same 1.11 source, so the .cmi
# hashes match — the prefix copy here is only used to *build* javalib), exactly
# like goblint's bigarray-compat living in both places.
#
# Chain (build order):  extlib (dune) + camlzip (make) -> javalib (make) -> sawja (make)
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${JS_SRC:-$(pwd)/vendor-javalib-sawja-src}"
PREFIX="${JS_PREFIX:?set JS_PREFIX to the per-runtime prefix dir}"

# clone_pinned — the version pins (extlib 1.8.0, camlzip rel111/zip 1.11 to match
# the lock, javalib 3.2.2, sawja 1.5.12) live in sources.yml as commits, so a
# re-pointed tag upstream cannot change what we build.
source "${MONOREPO_DIR}/scripts/lib-sources.sh"

mkdir -p "$SRC"
clone_pinned cppo    "$SRC/cppo"
clone_pinned extlib  "$SRC/extlib"
clone_pinned camlzip "$SRC/camlzip"
clone_pinned javalib "$SRC/javalib"
clone_pinned sawja   "$SRC/sawja"

# --- per-runtime build into PREFIX, opam-free ---
rm -rf "$PREFIX"; mkdir -p "$PREFIX/lib/stublibs" "$PREFIX/bin"
# pristine source per runtime: drop any build artifacts from another compiler
for d in cppo extlib camlzip javalib sawja; do
  git -C "$SRC/$d" clean -fdxq && git -C "$SRC/$d" checkout -q .
done
export OCAMLPATH="$PREFIX/lib" OCAMLFIND_DESTDIR="$PREFIX/lib" PATH="$PREFIX/bin:$PATH"
mkdir -p "$OCAMLFIND_DESTDIR"
echo "compiler: $(ocaml -version)"

# extlib 1.8.0's dune build preprocesses with cppo, so cppo must be on PATH.
# Rather than require `opam install cppo` in every runtime switch, build it from
# the pinned source into this prefix's bin/ (already prepended to PATH above), so
# the whole chain stays opam-free — the same model as extlib/javalib/sawja.
echo "[0/4] cppo (dune build -> PREFIX/bin, so extlib's build can find it)"
dune build --root "$SRC/cppo" --profile release src/cppo_main.exe
install -m755 "$SRC/cppo/_build/default/src/cppo_main.exe" "$PREFIX/bin/cppo"
command -v cppo >/dev/null 2>&1 || { echo "ERROR: cppo build did not land on PATH" >&2; exit 1; }

echo "[1/4] extlib (dune build @install)"
# --root isolates the build so dune doesn't adopt the enclosing macro-benches
# workspace (vendor/ lives inside it), as vendor-apron.sh does.
dune build --root "$SRC/extlib" --profile release @install
dune install --root "$SRC/extlib" --prefix "$PREFIX" --libdir "$PREFIX/lib" extlib

echo "[2/4] camlzip (make; findlib install -> PREFIX)"
( cd "$SRC/camlzip"
  make all
  make allopt
  make install )
echo "      $(ocamlfind query zip 2>&1) / $(ocamlfind query camlzip 2>&1)"

echo "[3/4] javalib (configure.sh -l PREFIX + make; needs extlib + camlzip)"
# -l PATH = local install: sets OCAMLFIND_DESTDIR + OCAMLPATH to PATH, so
# javalib installs into our prefix (not the switch, where it may already exist)
# and finds extlib/camlzip there.  Without it, `make install` errors with
# "Package javalib is already installed" against the switch.
( cd "$SRC/javalib"
  ./configure.sh -l "$PREFIX/lib"
  make
  make install )
echo "      $(ocamlfind query javalib 2>&1)"

echo "[4/4] sawja (configure.sh -l PREFIX + make; needs javalib)"
( cd "$SRC/sawja"
  ./configure.sh -l "$PREFIX/lib"
  make
  make install )
echo "      $(ocamlfind query sawja 2>&1)"
echo "PREFIX READY: $PREFIX"

# --- self-test: link sawja from PREFIX only (no switch libs) ---
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo '(lang dune 3.0)'                            > "$T/dune-project"
echo '(executable (name t) (libraries sawja))'   > "$T/dune"
echo 'let () = print_string "JAVALIB-SAWJA-PREFIX-OK\n"' > "$T/t.ml"
( cd "$T" && env OCAMLPATH="$PREFIX/lib" dune build ./t.exe \
  && CAML_LD_LIBRARY_PATH="$PREFIX/lib/stublibs" ./_build/default/t.exe )
