#!/usr/bin/env bash
# scripts/setup-stamp.sh --refresh, in a scratch repo with stand-in trees:
# a changed setup input removes them and the per-runtime build products, the
# same inputs keep them.
#
#   bash scripts/tests/test-setup-stamp.sh
set -u
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/benchmarks/foo"
cp "$ROOT_DIR/Makefile" "$ROOT_DIR/.gitignore" "$T/"
cp "$ROOT_DIR/scripts/setup-stamp.sh" "$T/scripts/"
echo "pin: 1" > "$T/sources.yml"
echo "echo build" > "$T/benchmarks/foo/foo.build.sh"
cd "$T" || exit 1
git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init

trees() {
    mkdir -p duniverse/x vendor/y _rocq_prefix _build-ocaml-a
    : > benchmarks/foo/foo-ocaml-a
    : > benchmarks/foo/foo-oxcaml-b
    : > benchmarks/foo/foo-ci.build-failed
}
refresh() { bash scripts/setup-stamp.sh --refresh >/dev/null; }

refresh
check "fresh tree: stamp written" '[ -s .setup-stamp ]'

trees; refresh
check "same inputs: trees kept" '[ -d duniverse/x ] && [ -d vendor/y ] && [ -e benchmarks/foo/foo-ocaml-a ]'

echo "pin: 2" > sources.yml
refresh
check "changed input: trees removed" '[ ! -e duniverse ] && [ ! -e vendor ] && [ ! -e _rocq_prefix ] && [ ! -e _build-ocaml-a ]'
check "changed input: binaries and sentinels removed" \
    '[ -z "$(ls benchmarks/foo | grep -v "^foo.build.sh$")" ]'
check "changed input: tracked files kept" '[ -f benchmarks/foo/foo.build.sh ] && [ -f sources.yml ]'
check "changed input: stamp updated" '[ "$(cat .setup-stamp)" = "$(bash scripts/setup-stamp.sh)" ]'

trees; rm -f .setup-stamp; refresh
check "no stamp: trees removed" '[ ! -e duniverse ] && [ ! -e benchmarks/foo/foo-oxcaml-b ]'

echo ""
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
