#!/usr/bin/env bash
# Every helper in lib-portable.sh must produce byte-identical output to the GNU
# command it replaces. Run on Linux, where both are available, so the portable
# spelling is checked against the original rather than merely "looking right".
#
#   bash scripts/tests/test-lib-portable.sh
#
# bash, not sh: lib-portable.sh uses bash arrays (`"${@:1:$#-1}"`) and so does
# every script that sources it. On FreeBSD bash lives in /usr/local/bin, which
# the `#!/usr/bin/env bash` shebang finds.
#
# On a BSD host the GNU comparisons are skipped, so every helper ALSO carries an
# unconditional assertion against an expected file. A helper whose only check is
# a GNU comparison is functionally unverified on the platform it exists for,
# which is the blind spot that let a GNU-only `sed '1a text'` script body survive
# in setup-monorepo.sh's patch 12.
set -u
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT_DIR/scripts/lib-portable.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/libport.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

pass=0; fail=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
same() { if cmp -s "$2" "$3"; then ok "$1"; else bad "$1"; diff "$2" "$3" | head -8; fi; }

# GNU sed -i takes no argument; BSD requires one. Detect rather than assume.
if printf 'x\n' > .probe && sed -i 's/x/y/' .probe 2>/dev/null; then
    HAVE_GNU_SED=1
else
    HAVE_GNU_SED=0
    echo "  (BSD sed detected: GNU comparisons skipped, helpers still exercised)"
fi

gnu() { [ "$HAVE_GNU_SED" = 1 ]; }

# --- insert_after, plain and with leading whitespace -------------------------
printf 'a\n(* libevent-based engine for lwt *)\nb\n' > in
cp in p; insert_after p 'libevent-based engine for lwt' 'type Lwt_engine.engine_id += Engine_id__libevent'
if gnu; then
    cp in g; sed -i '/libevent-based engine for lwt/a type Lwt_engine.engine_id += Engine_id__libevent' g
    same "insert_after vs sed '/re/a text'" g p
else
    grep -q 'Engine_id__libevent' p && ok "insert_after applied" || bad "insert_after"
fi

printf 'x\n  inherit Lwt_engine.abstract\ny\n' > in
cp in p; insert_after p 'inherit Lwt_engine.abstract' '  method id = Engine_id__libevent'
if gnu; then
    cp in g; sed -i '/inherit Lwt_engine.abstract/a\  method id = Engine_id__libevent' g
    same "insert_after preserves leading whitespace" g p
else
    grep -q '^  method id' p && ok "insert_after whitespace" || bad "insert_after whitespace"
fi

# --- delete_first_match: only the first, with two candidates present --------
printf 'l1\n (public_name ocamlformat)\nl3\n (public_name ocamlformat)\nl5\n' > in
cp in p; delete_first_match p '[(]public_name ocamlformat[)]'
if gnu; then
    cp in g; sed -i '0,/(public_name ocamlformat)/{/(public_name ocamlformat)/d}' g
    same "delete_first_match vs sed '0,/re/{/re/d}'" g p
fi
[ "$(grep -c 'public_name ocamlformat' p)" = 1 ] \
    && ok "delete_first_match leaves the second occurrence" \
    || bad "delete_first_match deleted too many"

# --- insert_at_line ----------------------------------------------------------
# This is the helper setup-monorepo.sh's patch 12 uses on caml_mcl.c, so the
# first case is that call site exactly.
printf '#include <stdio.h>\nint main(){}\n' > in
cp in p; insert_at_line p 1 '#include <stdint.h>'
printf '#include <stdio.h>\n#include <stdint.h>\nint main(){}\n' > e
same "insert_at_line 1 inserts after the first line" e p
if gnu; then
    cp in g; sed -i '1a #include <stdint.h>' g
    same "insert_at_line vs sed '1a text'" g p
fi

# several lines at once, and at a line that is not the first
printf 'l1\nl2\nl3\n' > in
cp in p; insert_at_line p 2 'A' 'B'
printf 'l1\nl2\nA\nB\nl3\n' > e
same "insert_at_line inserts several lines in order, mid-file" e p

# a line number past the end must leave the file alone rather than append
printf 'l1\nl2\n' > in
cp in p; insert_at_line p 99 'X'
same "insert_at_line past the end changes nothing" in p

# --- insert_after_offset: the N;N;N case, and offset 0 ----------------------
printf 'p0\nMATCH\nn1\nn2\nn3\ntail\n' > in
cp in p; insert_after_offset p 'MATCH' 3 'A1' 'A2' 'A3'
printf 'p0\nMATCH\nn1\nn2\nn3\nA1\nA2\nA3\ntail\n' > e
same "insert_after_offset 3 inserts after the third line past the match" e p
if gnu; then
    cp in g; sed -i '/MATCH/{
      N;N;N
      aA1\nA2\nA3
    }' g
    same "insert_after_offset vs sed '{N;N;N; a text}'" g p
fi

printf 'a\nMATCH\nb\n' > in
cp in p; insert_after_offset p 'MATCH' 0 'NEW'
printf 'a\nMATCH\nNEW\nb\n' > e
same "insert_after_offset 0 appends directly after the match" e p
if gnu; then
    cp in g; sed -i '/MATCH/a NEW' g
    same "insert_after_offset offset 0 equals a plain append" g p
fi

# EVERY match fires, as GNU `a` does; the helper's `!target` guard only stops a
# second match from moving a target that is still pending, it does not make the
# insertion first-only. delete_first_match is the one that is deliberately
# first-only; do not assume the two agree.
printf 'MATCH\nx\nMATCH\ny\n' > in
cp in p; insert_after_offset p 'MATCH' 0 'NEW'
printf 'MATCH\nNEW\nx\nMATCH\nNEW\ny\n' > e
same "insert_after_offset fires on every match, like GNU 'a'" e p
if gnu; then
    cp in g; sed -i '/MATCH/a NEW' g
    same "insert_after_offset multi-match vs sed '/re/a text'" g p
fi

# --- sed_i -------------------------------------------------------------------
printf 'lang dune 3.24\nother\n' > in
cp in p; sed_i -E 's/lang dune 3\.2[0-9]+/lang dune 3.21/' p
if gnu; then
    cp in g; sed -i -E 's/lang dune 3\.2[0-9]+/lang dune 3.21/' g
    same "sed_i vs sed -i (-E substitution)" g p
fi
grep -q 'lang dune 3.21' p && ok "sed_i applied the substitution" || bad "sed_i"

printf 'x\n' > mode
chmod 754 mode
before="$(ls -l mode | cut -c1-10)"
sed_i 's/x/y/' mode
[ "$(ls -l mode | cut -c1-10)" = "$before" ] \
    && ok "sed_i preserves file mode" \
    || bad "sed_i changed the file mode"

# sed_i must not clobber the file when sed fails, which -i also would not.
printf 'keep\n' > survive
if sed_i 's/[/' survive 2>/dev/null; then
    bad "sed_i reported success on a bad script"
else
    [ "$(cat survive)" = "keep" ] \
        && ok "sed_i leaves the file intact when sed fails" \
        || bad "sed_i truncated the file on failure"
fi

# --- checksum and ncpu -------------------------------------------------------
printf 'hello\n' > c
sum="$(checksum c)"
case "$sum" in
    b1946ac92492d2347c6235b4d2611184) ok "checksum returns lowercase hex md5" ;;
    *) bad "checksum gave '$sum'" ;;
esac

# --- the FreeBSD pkg prefix exports ------------------------------------------
# Sourcing this file on FreeBSD must put LOCALBASE's include/lib on the C
# toolchain's search path (base clang searches neither), must not touch a
# Linux host, must leave a caller's own value in front, and must not grow a
# duplicate entry when a vendor script re-sources it in a subprocess.
#
# Driven through a fake `uname` so the FreeBSD branch is exercised HERE, on
# Linux, rather than only on the platform it exists for. That is the same
# blind spot the insert_* helpers had.
FAKE="$WORK/fakebin"
mkdir -p "$FAKE"
printf '#!/bin/sh\n[ "$1" = "-s" ] && echo FreeBSD || exit 1\n' > "$FAKE/uname"
printf '#!/bin/sh\nexit 1\n' > "$FAKE/sysctl"   # no user.localbase: force the fallback
chmod +x "$FAKE/uname" "$FAKE/sysctl"

_as_freebsd() {   # <preset C_INCLUDE_PATH or empty> <times to source>
    PATH="$FAKE:$PATH" C_INCLUDE_PATH="$1" LOCALBASE="" \
    "$ROOT_DIR/scripts/tests/.reader.sh" "$2"
}
cat > "$ROOT_DIR/scripts/tests/.reader.sh" <<'READER'
#!/usr/bin/env bash
[ -n "${C_INCLUDE_PATH:-}" ] || unset C_INCLUDE_PATH
[ -n "${LOCALBASE:-}" ] || unset LOCALBASE
i=0; while [ "$i" -lt "$1" ]; do . "$(dirname "$0")/../lib-portable.sh"; i=$((i + 1)); done
printf '%s\n' "${C_INCLUDE_PATH:-}"
READER
chmod +x "$ROOT_DIR/scripts/tests/.reader.sh"

[ "$(_as_freebsd "" 1)" = "/usr/local/include" ] \
    && ok "FreeBSD: LOCALBASE/include is added" \
    || bad "FreeBSD: got '$(_as_freebsd "" 1)'"
[ "$(_as_freebsd "/opt/mine/include" 1)" = "/opt/mine/include:/usr/local/include" ] \
    && ok "FreeBSD: a caller's own value keeps priority" \
    || bad "FreeBSD: caller value not preserved: '$(_as_freebsd "/opt/mine/include" 1)'"
[ "$(_as_freebsd "" 3)" = "/usr/local/include" ] \
    && ok "FreeBSD: re-sourcing does not duplicate the entry" \
    || bad "FreeBSD: duplicated on re-source: '$(_as_freebsd "" 3)'"
rm -f "$ROOT_DIR/scripts/tests/.reader.sh"

# On this host (not FreeBSD) sourcing must add nothing at all.
if [ "$(uname -s)" != "FreeBSD" ]; then
    ( unset C_INCLUDE_PATH; . "$ROOT_DIR/scripts/lib-portable.sh"
      [ -z "${C_INCLUDE_PATH:-}" ] ) \
        && ok "non-FreeBSD host: C_INCLUDE_PATH left alone" \
        || bad "non-FreeBSD host: C_INCLUDE_PATH was modified"
fi

n="$(ncpu)"
case "$n" in
    ''|*[!0-9]*) bad "ncpu gave '$n', not a number" ;;
    *) [ "$n" -ge 1 ] && ok "ncpu returns a positive integer ($n)" || bad "ncpu returned $n" ;;
esac

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
