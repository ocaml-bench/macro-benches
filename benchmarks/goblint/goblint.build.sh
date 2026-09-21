#!/usr/bin/env bash
# goblint.build.sh: build Goblint (the ocaml#13733 GC-regression reproducer)
# from duniverse/analyzer and emit a wrapper. apron (needed by the svcomp
# config) is non-dune, so scripts/vendor-apron.sh builds it per runtime into a
# prefix exposed via OCAMLPATH. -std=gnu17 keeps GCC 15's C23 stddef.h
# (nullptr) parseable by goblint-cil.
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/goblint-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
APRON_PREFIX="${MONOREPO_DIR}/vendor/.apron_prefix-${RUNTIME_TAG}"

echo "Building goblint (monorepo) for runtime: ${RUNTIME_TAG}"

# 1. Per-runtime apron prefix (opam-free).
APRON_SRC="${MONOREPO_DIR}/vendor/.apron-src" \
APRON_PREFIX="${APRON_PREFIX}" \
  bash "${MONOREPO_DIR}/scripts/vendor-apron.sh"

# 2. Hermetic build: only the apron prefix is on OCAMLPATH.
unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH="${APRON_PREFIX}/lib"
dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/analyzer/src/goblint.exe

REAL_EXE="${BUILD_DIR}/default/duniverse/analyzer/src/goblint.exe"

# dune-site (Goblint_sites.lib_*) is only populated on `opam install`; the
# in-tree build leaves it empty and goblint aborts "custom include stdlib.c not
# found", so pre.custom_includes points at the vendored source dirs instead.
GLIB="${MONOREPO_DIR}/duniverse/analyzer/lib"

# Ladder inputs: bench.c (~0.2s) is too short for a rung, so generate a
# Btor2C-style bit-vector state machine with N state vars, masked so the
# analysis reaches a fixpoint. The octagon domain is O(N^2), so wall and
# allocation grow super-linearly (5.5.0: N=100 ~4s, 165 ~16s, 240 ~47s).
# Deterministic in N; gitignored.
gen_chain_c () {  # $1 = output .c, $2 = N
  python3 - "$2" "$1" << 'PY'
import sys
N = int(sys.argv[1]); out = sys.argv[2]
L = []
L.append('extern unsigned int __VERIFIER_nondet_uint();')
L.append('extern void abort(void);')
L.append('extern void __assert_fail(const char*,const char*,unsigned,const char*);')
L.append('void reach_error(){ __assert_fail("0","goblint_gen.c",0,"reach_error"); }')
L.append('void __VERIFIER_assert(int cond){ if(!(cond)){ ERROR: {reach_error(); abort();} } }')
L.append('int main(){')
L.append('  unsigned int ' + ', '.join(f's{i}=0u' for i in range(N)) + ';')
L.append('  unsigned int step=0u;')
L.append('  for(;;){')
for i in range(N):
    L.append(f'    unsigned int i{i}=__VERIFIER_nondet_uint()&0xFFFFu;')
for i in range(N):
    a, b = (i + 1) % N, (i + 2) % N
    L.append(f'    unsigned int n{i}=((s{i} ^ (s{a} + i{i})) + (s{b} & i{a}))&0xFFFFu;')
for i in range(0, N, 3):
    h = (i + N // 2) % N
    L.append(f'    if(i{i}&1u){{ n{i}=(n{i}+n{h})&0xFFFFu; }} else {{ n{i}=(n{i}^s{h})&0xFFFFu; }}')
for i in range(N):
    L.append(f'    s{i}=n{i};')
L.append('    step=(step+1u)&0xFFFFu;')
for i in range(0, N, 5):
    L.append(f'    __VERIFIER_assert(s{i}<=0xFFFFu);')
L.append('  }')
L.append('  return 0;')
L.append('}')
open(out, 'w').write('\n'.join(L) + '\n')
PY
}
for spec in "small:100" "default:165" "large:240"; do
  rung="${spec%%:*}"; n="${spec##*:}"
  gen_c="${BENCH_DIR}/goblint_gen_${rung}.c"
  if [[ ! -f "$gen_c" ]]; then
    echo "Generating goblint_gen_${rung}.c (state machine, N=${n})..."
    gen_chain_c "$gen_c" "$n"
  fi
done

# 3. Wrapper. The analysed file follows the output name: goblint_gen_<rung> or bench.c.
case "$(basename "${OUT}")" in
  *goblint_gen_small*)   TARGET_C="${BENCH_DIR}/goblint_gen_small.c" ;;
  *goblint_gen_default*) TARGET_C="${BENCH_DIR}/goblint_gen_default.c" ;;
  *goblint_gen_large*)   TARGET_C="${BENCH_DIR}/goblint_gen_large.c" ;;
  *)                     TARGET_C="${BENCH_DIR}/bench.c" ;;
esac

mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
# apron's 14 shared objects (libapron.so, libpolka*.so, liboct*.so, ...) sit
# directly in \${APRON_PREFIX}/lib; lib/apron holds only .a/.cma/.idl. goblint.exe
# normally resolves them through its RUNPATH, baked in at link time, so this is
# the fallback for a relocated or RUNPATH-stripped binary -- it has to name the
# directory the .so actually live in or it silently contributes nothing.
export CAML_LD_LIBRARY_PATH="${APRON_PREFIX}/lib/stublibs:${APRON_PREFIX}/lib/apron"
export LD_LIBRARY_PATH="${APRON_PREFIX}/lib:${APRON_PREFIX}/lib/apron\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
# Fail loudly if the prefix is gone. It is created by THIS script (step 1), not
# by setup-monorepo.sh, so anything that wipes vendor/ without rebuilding goblint
# leaves the RUNPATH dangling; without this check the only symptom is
# "error while loading shared libraries" and exit 127 on every invocation.
if [ ! -d "${APRON_PREFIX}/lib" ]; then
  echo "ERROR: apron prefix missing at ${APRON_PREFIX}" >&2
  echo "  rebuild it with: rm -f ${OUT} && <re-run the benchmark build>" >&2
  exit 1
fi
exec "${REAL_EXE}" \\
  --conf "${BENCH_DIR}/svcomp.json" \\
  --sets ana.specification "${BENCH_DIR}/unreach-call.prp" \\
  --sets exp.architecture 64bit \\
  --set pre.cppflags[+] -std=gnu17 \\
  --set pre.custom_includes[+] "${GLIB}/libc/stub/src" \\
  --set pre.custom_includes[+] "${GLIB}/libc/stub/include" \\
  --set pre.custom_includes[+] "${GLIB}/sv-comp/stub/src" \\
  --set pre.custom_includes[+] "${GLIB}/linux/stub/include" \\
  --set pre.custom_includes[+] "${GLIB}/goblint/runtime/include" \\
  "${TARGET_C}" "\$@"
WRAPPER
chmod +x "${OUT}"

echo "goblint built: ${OUT} (analysing $(basename "${TARGET_C}"))"
