#!/usr/bin/env bash
# Every per-benchmark build script must source scripts/lib-portable.sh.
#
#   bash scripts/tests/test-build-scripts-portable.sh
#
# Why this is a rule rather than a convention. setup-monorepo.sh sources
# lib-sources.sh, which sources lib-portable.sh, so everything reached through
# `make setup` gets the LOCALBASE exports. But running-ng invokes
# benchmarks/<suite>/<suite>.build.sh DIRECTLY at run time, in a fresh process
# that inherits none of that. A build script without this line therefore works
# during setup and fails at run time, on FreeBSD only, with a missing-header
# error for a package that is definitely installed:
#
#   event_stubs.c:13:10: fatal error: 'event.h' file not found
#
# That is what happened to devkit: it built during `make setup` [9/9] and then
# could not build when running-ng called it.
#
# It costs nothing on Linux, where the export is gated off entirely, which is
# also why a missing line cannot be noticed here without this check.
set -u
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

shopt -s nullglob
scripts=(benchmarks/*/*.build.sh)
if [ "${#scripts[@]}" -eq 0 ]; then
    echo "  FAIL  no build scripts found under benchmarks/ (wrong cwd?)"
    exit 1
fi

for f in "${scripts[@]}"; do
    if grep -q 'scripts/lib-portable\.sh' "$f"; then
        ok "$(basename "$f") sources lib-portable.sh"
    else
        bad "$(basename "$f") does NOT source lib-portable.sh (see this file's header)"
    fi
done

# The line has to actually work, not merely be present: a build script sits two
# levels below the repo root, so the relative path must resolve from there.
for f in "${scripts[@]}"; do
    resolved="$(cd "$(dirname "$f")/../.." && pwd)/scripts/lib-portable.sh"
    [ -f "$resolved" ] || bad "$(basename "$f"): ../../scripts/lib-portable.sh does not resolve"
done

# And every one must still be valid bash after the insertion.
for f in "${scripts[@]}"; do
    bash -n "$f" 2>/dev/null || bad "$(basename "$f") is not valid bash"
done

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
