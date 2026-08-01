#!/usr/bin/env bash
# alt-ergo.build.sh — build alt-ergo from the macro-benches monorepo.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/alt-ergo-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
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

# ----------------------------------------------------------------------
# Knob-A congruence-chain ladder (alt_ergo_chain_{small,default,large}).
#
# fill_x100 above is a Knob-B input (100 independent copies of one goal:
# peak working set constant, wall linear). The chain rungs are Knob A: a
# SINGLE goal whose working set grows with N. The goal asserts a chain
# a(0)=0 and a(i)=a(i-1)+1 for i in 1..N and proves a(N)=N, so alt-ergo
# builds an N-term congruence/arithmetic structure in one solve. This is
# the same array-cell reasoning fill.why exercises (Frama-C/WP VCs),
# parameterised. Solving is super-linear (~N^2.2 in both wall and live
# heap): N=4000 ~4s/0.6GB, 7000 ~13s/1.9GB, 10500 ~32s/5.0GB on 5.5.0.
# Outputs are gitignored; generated once (deterministic in N).
# ----------------------------------------------------------------------
gen_chain () {  # $1 = output file, $2 = N
  python3 - "$2" "$1" <<'PY'
import sys
N = int(sys.argv[1]); out = sys.argv[2]
hyp = " and ".join(f"a({i}) = a({i-1}) + 1" for i in range(1, N + 1))
with open(out, "w") as f:
    f.write("logic a : int -> int\n")
    f.write(f"goal g : (a(0) = 0 and {hyp}) -> a({N}) = {N}\n")
PY
}
for spec in "small:4000" "default:7000" "large:10500"; do
  rung="${spec%%:*}"; n="${spec##*:}"
  chain_out="${BENCH_DIR}/alt_ergo_chain_${rung}.why"
  if [[ ! -f "$chain_out" ]]; then
    echo "Generating alt_ergo_chain_${rung}.why (congruence chain, N=${n})..."
    gen_chain "$chain_out" "$n"
  fi
done

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/alt-ergo/src/bin/text/Main_text.exe

mkdir -p "$(dirname "${OUT}")"
cp "${BUILD_DIR}/default/duniverse/alt-ergo/src/bin/text/Main_text.exe" "${OUT}"
chmod +x "${OUT}"

echo "alt-ergo built: ${OUT}"
