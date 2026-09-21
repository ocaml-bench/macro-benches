#!/usr/bin/env bash
# Vendor + build the apron chain (camlidl, mlgmpidl, apron, plus bigarray-compat
# so the prefix is self-contained) without opam: configure + make, per-runtime,
# into a prefix that goblint.build.sh points OCAMLPATH at.
# Env: APRON_PREFIX (required) per-runtime prefix dir; APRON_SRC clone dir.
set -euo pipefail

SRC="${APRON_SRC:-$(pwd)/vendor-apron-src}"
PREFIX="${APRON_PREFIX:?set APRON_PREFIX to the per-runtime prefix dir}"

# Skip when already built for this compiler: running-ng calls goblint.build.sh
# once per program, so the chain would otherwise be rebuilt four times. The
# stamp records the compiler; delete the prefix or the stamp to force a rebuild.
_stamp="$PREFIX/.apron-stamp"
_want="apron-prefix v1 $(ocaml -version 2>/dev/null)"
if [ -f "$_stamp" ] && [ "$(cat "$_stamp" 2>/dev/null)" = "$_want" ] \
   && [ -d "$PREFIX/lib/apron" ]; then
  # Keep this distinguishable from the build path's final line.
  echo "apron prefix: CACHED, no rebuild (stamp matches $(ocaml -version 2>/dev/null)): $PREFIX"
  exit 0
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib-sources.sh"
mkdir -p "$SRC"
for _pkg in bigarray-compat camlidl mlgmpidl apron; do
  clone_pinned "$_pkg" "$SRC/$_pkg"
done

# camlidl's Makefile uses GNU conditionals that FreeBSD's bmake rejects.
MAKE="$(gnu_make)"

# Stage output is captured, not discarded, so a failing stage reports its last
# lines here instead of surfacing later as a missing goblint.
die_stage() {   # <label> <logfile>
  echo "ERROR: $1 failed (goblint needs apron, which needs all four stages)." >&2
  echo "---- last 25 lines of its output ----" >&2
  tail -25 "$2" >&2
  exit 1
}

# mlgmpidl/apron need mpfr.h at build time. Without the distro -dev package,
# build MPFR from pinned source once into a shared compiler-independent prefix;
# -rpath lets the stubs find it even with no system libmpfr. Left empty when the
# system provides mpfr.h.
MPFR_CPPFLAGS=""; MPFR_LDFLAGS=""
if ! printf '#include <mpfr.h>\n' | "${CC:-cc}" -E - >/dev/null 2>&1; then
  MPFR_PREFIX="${MPFR_PREFIX:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vendor/.mpfr-prefix}"
  if [ ! -f "$MPFR_PREFIX/include/mpfr.h" ]; then
    echo "[mpfr] system mpfr.h absent; building MPFR $(src_field mpfr version) into $MPFR_PREFIX"
    _mpfr_t="$(mktemp -d)"
    curl -fsSL "$(src_field mpfr url)" -o "$_mpfr_t/mpfr.tar.xz"
    tar --no-same-owner -xf "$_mpfr_t/mpfr.tar.xz" -C "$_mpfr_t"
    _ncpu="$(ncpu)"
    _mpfr_log="$(mktemp)"
    ( cd "$_mpfr_t/mpfr-$(src_field mpfr version)"
      ./configure --prefix="$MPFR_PREFIX" --disable-static --enable-shared
      "$MAKE" -j"$_ncpu" && "$MAKE" install ) >"$_mpfr_log" 2>&1 \
      || die_stage "MPFR build" "$_mpfr_log"
    rm -f "$_mpfr_log"
    rm -rf "$_mpfr_t"
  fi
  MPFR_CPPFLAGS="-I$MPFR_PREFIX/include"
  MPFR_LDFLAGS="-L$MPFR_PREFIX/lib -Wl,-rpath,$MPFR_PREFIX/lib"
  echo "[mpfr] using $MPFR_PREFIX"
fi

rm -rf "$PREFIX"; mkdir -p "$PREFIX/lib/caml" "$PREFIX/lib/stublibs" "$PREFIX/bin"
# Drop build artifacts left by another compiler.
for d in bigarray-compat camlidl mlgmpidl apron; do git -C "$SRC/$d" clean -fdxq && git -C "$SRC/$d" checkout -q .; done
export OCAMLPATH="$PREFIX/lib" OCAMLFIND_DESTDIR="$PREFIX/lib" PATH="$PREFIX/bin:$PATH"
echo "compiler: $(ocaml -version)"

echo "[1/4] bigarray-compat (dune)"
# --root keeps dune from adopting the enclosing macro-benches workspace.
_log="$(mktemp)"
( dune build --root "$SRC/bigarray-compat" --profile release @install \
  && dune install --root "$SRC/bigarray-compat" --prefix "$PREFIX" --libdir "$PREFIX/lib" bigarray-compat ) \
  >"$_log" 2>&1 || die_stage "bigarray-compat build" "$_log"
rm -f "$_log"
echo "      $(ocamlfind query bigarray-compat 2>&1)"

echo "[2/4] camlidl (make build; findlib install)"
_log="$(mktemp)"
( cd "$SRC/camlidl"
  [ -f config/Makefile ] || cp config/Makefile.unix config/Makefile
  "$MAKE" all
  cp compiler/camlidl "$PREFIX/bin/"
  files="META lib/com.cmi lib/com.cma lib/com.cmxa runtime/libcamlidl.a runtime/camlidlruntime.h"
  [ -f lib/com.a ] && files="$files lib/com.a"
  ocamlfind install camlidl $files
  cp runtime/camlidlruntime.h "$PREFIX/lib/caml/"
  mkdir -p "$PREFIX/lib/camlidl/caml"
  cp runtime/camlidlruntime.h "$PREFIX/lib/camlidl/caml/" ) \
  >"$_log" 2>&1 || die_stage "camlidl build" "$_log"   # apron configure looks in lib/camlidl/caml
rm -f "$_log"
echo "      $(ocamlfind query camlidl 2>&1)"

echo "[3/4] mlgmpidl (configure/make; needs camlidl + caml/camlidlruntime.h)"
_log="$(mktemp)"
( cd "$SRC/mlgmpidl"
  ./configure CPPFLAGS+=" -I$PREFIX/lib $MPFR_CPPFLAGS" LDFLAGS+=" $MPFR_LDFLAGS"
  "$MAKE" && "$MAKE" install ) >"$_log" 2>&1 || die_stage "mlgmpidl build" "$_log"
rm -f "$_log"
echo "      $(ocamlfind query gmp 2>&1)"

echo "[4/4] apron (configure --prefix; finds camlidl via ocamlfind query)"
_log="$(mktemp)"
( cd "$SRC/apron"
  # apron's configure ignores CPPFLAGS for mpfr and wants MPFR_PREFIX; leave it
  # unset to use system mpfr.
  [ -n "${MPFR_PREFIX:-}" ] && export MPFR_PREFIX
  CPPFLAGS="-I$PREFIX/lib $MPFR_CPPFLAGS" LDFLAGS="$MPFR_LDFLAGS" ./configure --prefix "$PREFIX" --no-ppl --no-strip
  # Serial make: apron's recursive Makefile under-declares the OCaml bindings'
  # dependency on the C libraries, so -j races and intermittently fails with
  # exit 2 (mlgmpidl above is serial for the same reason).
  "$MAKE" && "$MAKE" install ) >"$_log" 2>&1 || die_stage "apron build" "$_log"
rm -f "$_log"
echo "      $(ocamlfind query apron 2>&1)"
echo "      C libs: $(find "$PREFIX" -name 'libapron*.a' | head -1)"
echo "apron prefix: BUILT from source: $PREFIX"

# Self-test: link apron from PREFIX only.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo '(lang dune 3.0)'                              > "$T/dune-project"
echo '(executable (name t) (libraries apron.boxMPQ))' > "$T/dune"
echo 'let () = let _ = Box.manager_alloc () in print_string "APRON-PREFIX-OK\n"' > "$T/t.ml"
( cd "$T" && env OCAMLPATH="$PREFIX/lib" dune build ./t.exe >/dev/null 2>&1 \
  && CAML_LD_LIBRARY_PATH="$PREFIX/lib/stublibs" ./_build/default/t.exe )

# Stamp last, after the self-test, so a half-built prefix is never skipped as good.
printf '%s\n' "$_want" > "$_stamp"
