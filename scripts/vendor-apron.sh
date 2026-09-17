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

# --- already built for this compiler?  then do nothing ---
# goblint.build.sh calls this script unconditionally, and running-ng calls
# goblint.build.sh once per BENCHMARK, so four goblint programs rebuilt the
# whole chain four times: mpfr, camlidl, mlgmpidl and apron, plus a `git clean`
# of the shared source trees under $SRC on every pass. That is slow, and it
# means any transient failure in the chain repeats for each remaining program
# instead of once.
#
# The stamp records the compiler the prefix was built with. $PREFIX is already
# per-runtime (.apron_prefix-<runtime tag>), so the only way a stale prefix can
# be reused is if the same tag is rebuilt with a different compiler, which the
# stamp catches. Delete the prefix, or the stamp, to force a rebuild.
_stamp="$PREFIX/.apron-stamp"
_want="apron-prefix v1 $(ocaml -version 2>/dev/null)"
if [ -f "$_stamp" ] && [ "$(cat "$_stamp" 2>/dev/null)" = "$_want" ] \
   && [ -d "$PREFIX/lib/apron" ]; then
  # One line, and it must not be mistakable for a build. The first version of
  # this printed "PREFIX READY" here too, which is what the BUILD path ends
  # with, so a skip read as a rebuild in the logs and the guard looked broken
  # when it was working. Nothing parses either string; they are for humans.
  echo "apron prefix: CACHED, no rebuild (stamp matches $(ocaml -version 2>/dev/null)): $PREFIX"
  exit 0
fi

# --- pins live in sources.yml (by commit, not by tag: a tag can be re-pointed) ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib-sources.sh"
mkdir -p "$SRC"
for _pkg in bigarray-compat camlidl mlgmpidl apron; do
  clone_pinned "$_pkg" "$SRC/$_pkg"
done

# GNU make, not whatever `make` is. camlidl's Makefile uses GNU conditionals
# that FreeBSD's bmake rejects as a syntax error, and mlgmpidl's and apron's
# are GNU-flavoured too. Resolves to plain `make` on Linux. See lib-portable.sh.
MAKE="$(gnu_make)"

# Build stages are verbose, so their output is CAPTURED. Capture is not
# discard: every `make` here used to go to /dev/null, so when camlidl failed on
# FreeBSD the entire log was nine lines ending at "[2/4] camlidl" with no error
# at all, and goblint's absence surfaced much later as something unrelated.
# That is the same "symptom several steps removed from the cause" the patch 15
# comment in setup-monorepo.sh already warns about. A stage that fails now says
# so, here, with its last lines.
die_stage() {   # <label> <logfile>
  echo "ERROR: $1 failed (goblint needs apron, which needs all four stages)." >&2
  echo "---- last 25 lines of its output ----" >&2
  tail -25 "$2" >&2
  exit 1
}

# --- MPFR: mlgmpidl/apron need mpfr.h + libmpfr.so at BUILD time (see sources.yml).
# On a no-sudo box the distro -dev package may be missing (only the runtime
# libmpfr.so.N is present), so build MPFR from pinned source once into a shared,
# compiler-independent prefix and point the mlgmpidl/apron configures at it. When
# the system already provides mpfr.h this stays empty and system MPFR is used as
# before. The -rpath makes the built stubs find our libmpfr even on a box with no
# system libmpfr at all.
MPFR_CPPFLAGS=""; MPFR_LDFLAGS=""
if ! printf '#include <mpfr.h>\n' | "${CC:-cc}" -E - >/dev/null 2>&1; then
  MPFR_PREFIX="${MPFR_PREFIX:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vendor/.mpfr-prefix}"
  if [ ! -f "$MPFR_PREFIX/include/mpfr.h" ]; then
    echo "[mpfr] system mpfr.h absent; building MPFR $(src_field mpfr version) into $MPFR_PREFIX"
    _mpfr_t="$(mktemp -d)"
    curl -fsSL "$(src_field mpfr url)" -o "$_mpfr_t/mpfr.tar.xz"
    tar xf "$_mpfr_t/mpfr.tar.xz" -C "$_mpfr_t"
    # One spelling for this, in lib-portable.sh, so there is a single
    # place to fix if a platform needs a third fallback.
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

# --- per-runtime build into PREFIX, opam-free ---
rm -rf "$PREFIX"; mkdir -p "$PREFIX/lib/caml" "$PREFIX/lib/stublibs" "$PREFIX/bin"
# pristine source per runtime: drop any build artifacts from another compiler
for d in bigarray-compat camlidl mlgmpidl apron; do git -C "$SRC/$d" clean -fdxq && git -C "$SRC/$d" checkout -q .; done
export OCAMLPATH="$PREFIX/lib" OCAMLFIND_DESTDIR="$PREFIX/lib" PATH="$PREFIX/bin:$PATH"
echo "compiler: $(ocaml -version)"

echo "[1/4] bigarray-compat (dune)"
# --root isolates the build: without it, dune walks up and adopts the enclosing
# macro-benches workspace as root (vendor/ lives inside it), breaking the build.
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
  # apron's configure does not honour CPPFLAGS for mpfr; it wants MPFR_PREFIX
  # (searching /usr/local /opt/homebrew /usr $HOME otherwise). Pass ours when we
  # built MPFR from source; leave it unset so apron finds system mpfr as before.
  [ -n "${MPFR_PREFIX:-}" ] && export MPFR_PREFIX
  CPPFLAGS="-I$PREFIX/lib $MPFR_CPPFLAGS" LDFLAGS="$MPFR_LDFLAGS" ./configure --prefix "$PREFIX" --no-ppl --no-strip
  # Serial make: apron's recursive Makefile under-declares the dependency of the
  # OCaml bindings on the C domain libraries, so a parallel build (-j) races and
  # intermittently dies with exit 2 — reliably enough to fail CI now and then while
  # passing locally and on master. The build is small; serial costs little and is
  # the only race-free option for a Makefile with missing deps (mlgmpidl above is
  # serial for the same reason). Do NOT reintroduce -j here.
  "$MAKE" && "$MAKE" install ) >"$_log" 2>&1 || die_stage "apron build" "$_log"
rm -f "$_log"
echo "      $(ocamlfind query apron 2>&1)"
echo "      C libs: $(find "$PREFIX" -name 'libapron*.a' | head -1)"
echo "apron prefix: BUILT from source: $PREFIX"

# --- hermetic self-test: link apron from PREFIX only (no switch libs) ---
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo '(lang dune 3.0)'                              > "$T/dune-project"
echo '(executable (name t) (libraries apron.boxMPQ))' > "$T/dune"
echo 'let () = let _ = Box.manager_alloc () in print_string "APRON-PREFIX-OK\n"' > "$T/t.ml"
( cd "$T" && env OCAMLPATH="$PREFIX/lib" dune build ./t.exe >/dev/null 2>&1 \
  && CAML_LD_LIBRARY_PATH="$PREFIX/lib/stublibs" ./_build/default/t.exe )

# Stamp LAST, and only after the self-test has linked apron out of this prefix.
# A stamp written earlier would let a half-built prefix be skipped as good.
printf '%s\n' "$_want" > "$_stamp"
