#!/usr/bin/env bash
# alt-ergo.build.sh: build alt-ergo and generate its inputs.
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/alt-ergo-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building alt-ergo (monorepo) for runtime: ${RUNTIME_TAG}"

# alt_ergo_fill input: replicate fill.why's single goal 100 times under new names
# (~0.14s/goal). Done before the dune build so it runs regardless of compiler
# status. Gitignored; regenerated when fill.why changes.
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

# Chain ladder: one goal asserting a(0)=0, a(i)=a(i-1)+1 and proving a(N)=N, so
# the working set grows with N (super-linear, ~N^2.2: 4000 ~4s/0.6GB, 7000
# ~13s/1.9GB, 10500 ~32s/5GB on 5.5.0). Deterministic in N; gitignored.
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
