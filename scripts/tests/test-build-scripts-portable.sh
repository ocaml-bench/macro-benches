#!/usr/bin/env bash
# Every per-benchmark build script must source scripts/lib-portable.sh.
#
#   bash scripts/tests/test-build-scripts-portable.sh
#
# running-ng invokes benchmarks/<suite>/<suite>.build.sh directly, in a fresh
# process without the LOCALBASE exports `make setup` provides, so a script
# missing the line builds during setup but fails at run time on FreeBSD with
#   event_stubs.c:13:10: fatal error: 'event.h' file not found
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

# The relative path must resolve from two levels below the repo root.
for f in "${scripts[@]}"; do
    resolved="$(cd "$(dirname "$f")/../.." && pwd)/scripts/lib-portable.sh"
    [ -f "$resolved" ] || bad "$(basename "$f"): ../../scripts/lib-portable.sh does not resolve"
done

for f in "${scripts[@]}"; do
    bash -n "$f" 2>/dev/null || bad "$(basename "$f") is not valid bash"
done

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
