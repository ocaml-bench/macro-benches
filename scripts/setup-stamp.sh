#!/usr/bin/env bash
# The inputs of setup-monorepo.sh, hashed: every tracked file that shapes what
# it writes (duniverse/, vendor/, _rocq_prefix/).
#
# Usage: bash scripts/setup-stamp.sh            print the hash (CI's cache key)
#        bash scripts/setup-stamp.sh --refresh  start over if .setup-stamp differs
#
# Each setup step skips when its output exists, so a tree set up from other
# inputs (a pin bump, a changed patch) would otherwise survive. --refresh removes
# it, with every per-runtime product built against it, then records the hash.
# The same inputs leave the tree alone, so an interrupted setup resumes.
set -euo pipefail
cd "$(dirname "$0")/.."

INPUTS=(
  macro-benches.opam.locked sources.yml dune-project dune-overlays
  scripts/setup-monorepo.sh scripts/setup-oxcaml.sh scripts/setup-stamp.sh
  'scripts/vendor-*.sh' scripts/lib-sources.sh scripts/lib-switch.sh
  scripts/lib-portable.sh scripts/ppx-expand.sh scripts/ppx-expand
)

# Working-tree contents, so a local edit to a setup script counts too.
hash="$(git ls-files -z -- "${INPUTS[@]}" | python3 -c '
import hashlib, sys
h = hashlib.sha256()
for path in sorted(p for p in sys.stdin.buffer.read().split(b"\0") if p):
    h.update(path + b"\0")
    with open(path, "rb") as f:
        h.update(hashlib.sha256(f.read()).digest())
print(h.hexdigest())
')"

if [ "${1:-}" != "--refresh" ]; then
  echo "$hash"
  exit 0
fi

if { [ -e duniverse ] || [ -e vendor ] || [ -e _rocq_prefix ]; } \
   && [ "$(cat .setup-stamp 2>/dev/null)" != "$hash" ]; then
  echo "Setup inputs changed since this tree was set up: removing duniverse/,"
  echo "vendor/, _rocq_prefix/, _build*/ and the build products under benchmarks/."
  make -s clean-all
  git clean -fdXq -- benchmarks/
fi
echo "$hash" > .setup-stamp
