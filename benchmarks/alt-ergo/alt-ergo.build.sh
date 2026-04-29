#!/usr/bin/env bash
# alt-ergo.build.sh — build alt-ergo from the macro-benches monorepo.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/alt-ergo-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="${RUNNING_MACRO_MONOREPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building alt-ergo (monorepo) for runtime: ${RUNTIME_TAG}"

# ----------------------------------------------------------------------
# alt_ergo_fill input scaling — done BEFORE dune build so it always
# runs independently of compiler/build status.
#
# fill.why has a single goal `fill_assert_39`. Replicate the goal
# block N times with renamed identifiers so alt-ergo solves each
# independently — work scales linearly. Runs ~0.14s/goal on this
# machine, so N=100 ≈ 14 s wall.
#
# Output is gitignored. Regenerated only when fill.why changes.
# ----------------------------------------------------------------------
FILL_SRC="${BENCH_DIR}/fill.why"
FILL_X100="${BENCH_DIR}/fill_x100.why"
if [[ -f "$FILL_SRC" ]] && { [[ ! -f "$FILL_X100" ]] || [[ "$FILL_SRC" -nt "$FILL_X100" ]]; }; then
  echo "Generating fill_x100.why (100 replicated goals from fill.why)..."
  python3 - "$FILL_SRC" "$FILL_X100" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
fill = open(src).read()
m = re.search(r'\n\(\* -+ \*\)\s*\ngoal fill_assert_39:', fill)
if m is None:
    sys.exit("fill.why: could not locate goal fill_assert_39")
preamble = fill[:m.start()]
goal_body = fill[m.start():]
N = 100
parts = [preamble]
for i in range(1, N + 1):
    parts.append(goal_body.replace('goal fill_assert_39:', f'goal fill_assert_{i}:'))
open(dst, 'w').write('\n'.join(parts))
PY
  echo "fill_x100.why generated: $(wc -l < "$FILL_X100") lines, $(grep -c '^goal ' "$FILL_X100") goals."
fi

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/alt-ergo/src/bin/text/Main_text.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/duniverse/alt-ergo/src/bin/text/Main_text.exe" "${OUT}"
chmod +x "${OUT}"

echo "alt-ergo built: ${OUT}"
