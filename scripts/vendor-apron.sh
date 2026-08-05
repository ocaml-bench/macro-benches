#!/usr/bin/env bash
# vendor-apron.sh — vendor + build the apron chain WITHOUT opam.
#
# apron is the monorepo's first non-dune vendored dependency: apron, mlgmpidl
# and camlidl build via ./configure + make, not dune, so they can't join the
# unified dune build the way frama-c does.  Instead we vendor their source at
# pinned tags (the clone tag == the pin) and build them per-runtime, with ONLY
# the active OCaml compiler + gcc + ocamlfind + make, into a self-contained
# prefix.  goblint.build.sh then points OCAMLPATH at that prefix alone, so the
# hermetic (OCAMLPATH="") duniverse build links our vendored apron and nothing
# else from the switch.  No opam, no solver, no repos -> works on any runtime
# (trunk, PR branches) exactly like duniverse/, preserving "same source, only
# the runtime changes".
#
# bigarray-compat is pure dune; in the monorepo it lives in duniverse/, but we
# also build it here so the apron prefix is self-contained for standalone use.
set -euo pipefail

SRC="${APRON_SRC:-$(pwd)/vendor-apron-src}"
PREFIX="${APRON_PREFIX:?set APRON_PREFIX to the per-runtime prefix dir}"

# --- pins live in sources.yml (by commit, not by tag: a tag can be re-pointed) ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib-sources.sh"
mkdir -p "$SRC"
for _pkg in bigarray-compat camlidl mlgmpidl apron; do
  clone_pinned "$_pkg" "$SRC/$_pkg"
done

# --- per-runtime build into PREFIX, opam-free ---
rm -rf "$PREFIX"; mkdir -p "$PREFIX/lib/caml" "$PREFIX/lib/stublibs" "$PREFIX/bin"
# pristine source per runtime: drop any build artifacts from another compiler
for d in bigarray-compat camlidl mlgmpidl apron; do git -C "$SRC/$d" clean -fdxq && git -C "$SRC/$d" checkout -q .; done
export OCAMLPATH="$PREFIX/lib" OCAMLFIND_DESTDIR="$PREFIX/lib" PATH="$PREFIX/bin:$PATH"
echo "compiler: $(ocaml -version)"

echo "[1/4] bigarray-compat (dune)"
# --root isolates the build: without it, dune walks up and adopts the enclosing
# macro-benches workspace as root (vendor/ lives inside it), breaking the build.
( dune build --root "$SRC/bigarray-compat" --profile release @install >/dev/null 2>&1 \
  && dune install --root "$SRC/bigarray-compat" --prefix "$PREFIX" --libdir "$PREFIX/lib" bigarray-compat >/dev/null 2>&1 )
echo "      $(ocamlfind query bigarray-compat 2>&1)"

echo "[2/4] camlidl (make build; findlib install)"
( cd "$SRC/camlidl"
  [ -f config/Makefile ] || cp config/Makefile.unix config/Makefile
  make all >/dev/null 2>&1
  cp compiler/camlidl "$PREFIX/bin/"
  files="META lib/com.cmi lib/com.cma lib/com.cmxa runtime/libcamlidl.a runtime/camlidlruntime.h"
  [ -f lib/com.a ] && files="$files lib/com.a"
  ocamlfind install camlidl $files >/dev/null 2>&1
  cp runtime/camlidlruntime.h "$PREFIX/lib/caml/"
  mkdir -p "$PREFIX/lib/camlidl/caml"
  cp runtime/camlidlruntime.h "$PREFIX/lib/camlidl/caml/" )           # apron configure looks here
echo "      $(ocamlfind query camlidl 2>&1)"

echo "[3/4] mlgmpidl (configure/make; needs camlidl + caml/camlidlruntime.h)"
( cd "$SRC/mlgmpidl"
  ./configure CPPFLAGS+=-I"$PREFIX/lib" >/dev/null 2>&1
  make >/dev/null 2>&1 && make install >/dev/null 2>&1 )
echo "      $(ocamlfind query gmp 2>&1)"

echo "[4/4] apron (configure --prefix; finds camlidl via ocamlfind query)"
( cd "$SRC/apron"
  CPPFLAGS="-I$PREFIX/lib" ./configure --prefix "$PREFIX" --no-ppl --no-strip >/dev/null 2>&1
  # Serial make: apron's recursive Makefile under-declares the dependency of the
  # OCaml bindings on the C domain libraries, so a parallel build (-j) races and
  # intermittently dies with exit 2 — reliably enough to fail CI now and then while
  # passing locally and on master. The build is small; serial costs little and is
  # the only race-free option for a Makefile with missing deps (mlgmpidl above is
  # serial for the same reason). Do NOT reintroduce -j here.
  make >/dev/null 2>&1 && make install >/dev/null 2>&1 )
echo "      $(ocamlfind query apron 2>&1)"
echo "      C libs: $(find "$PREFIX" -name 'libapron*.a' | head -1)"
echo "PREFIX READY: $PREFIX"

# --- hermetic self-test: link apron from PREFIX only (no switch libs) ---
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo '(lang dune 3.0)'                              > "$T/dune-project"
echo '(executable (name t) (libraries apron.boxMPQ))' > "$T/dune"
echo 'let () = let _ = Box.manager_alloc () in print_string "APRON-PREFIX-OK\n"' > "$T/t.ml"
( cd "$T" && env OCAMLPATH="$PREFIX/lib" dune build ./t.exe >/dev/null 2>&1 \
  && CAML_LD_LIBRARY_PATH="$PREFIX/lib/stublibs" ./_build/default/t.exe )
