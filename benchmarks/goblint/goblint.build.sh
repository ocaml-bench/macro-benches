#!/usr/bin/env bash
# goblint.build.sh — build the Goblint SV-COMP benchmark from the monorepo.
#
# Goblint (ocaml#13733) is a static analyser; on OCaml 5.x it exhibits the
# allocation/GC regression tracked in that issue (the sibling of frama-c's
# ocaml#11733).  Goblint + goblint-cil + ~60 deps are vendored via
# opam-monorepo (duniverse/analyzer, duniverse/cil).  apron — required by the
# svcomp config — is non-dune, so it is built per-runtime from vendored source
# into a self-contained prefix by scripts/vendor-apron.sh and exposed to the
# otherwise-hermetic dune build via OCAMLPATH (apron chain only).
#
# Runtime workload (one extreme SV-COMP outlier from the issue):
#   goblint --conf svcomp.json --sets ana.specification unreach-call.prp
#           --sets exp.architecture 64bit --set pre.cppflags[+] -std=gnu17 bench.c
# -std=gnu17 keeps GCC 15's C23 stddef.h (nullptr) parseable by goblint-cil.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/goblint-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"
APRON_PREFIX="${MONOREPO_DIR}/vendor/.apron_prefix-${RUNTIME_TAG}"

echo "Building goblint (monorepo) for runtime: ${RUNTIME_TAG}"

# 1. Build the vendored apron chain into a per-runtime prefix (opam-free:
#    only the active compiler + gcc + ocamlfind + make).
APRON_SRC="${MONOREPO_DIR}/vendor/.apron-src" \
APRON_PREFIX="${APRON_PREFIX}" \
  bash "${MONOREPO_DIR}/scripts/vendor-apron.sh"

# 2. Build goblint hermetically.  The duniverse deps come from the in-tree
#    dune workspace (not the switch); only the apron prefix is on OCAMLPATH.
unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH="${APRON_PREFIX}/lib"
dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  duniverse/analyzer/src/goblint.exe

REAL_EXE="${BUILD_DIR}/default/duniverse/analyzer/src/goblint.exe"

# Goblint locates its bundled libc/sv-comp/linux stubs + runtime includes via
# dune-site (Goblint_sites.lib_*), populated only on `opam install`.  Our
# hermetic in-tree build never installs, so those sites are empty and goblint
# aborts ("custom include stdlib.c not found").  Point pre.custom_includes (which
# goblint searches first) at the vendored source dirs instead.
GLIB="${MONOREPO_DIR}/duniverse/analyzer/lib"

# Knob-A generated inputs (goblint_gen_{small,default,large}).
#
# The frozen `goblint` program analyses the fixed #13733 reproducer bench.c
# (~0.2s here — too short for a macro rung). The Knob-A axis is the SIZE of the
# analysed program: a bigger C program means more variables tracked by the
# interval+octagon (apron) domains and more program points, so goblint's
# constraint solver does proportionally more fixpoint work. gen_goblint.py emits
# a synthetic Btor2C-style bit-vector state machine (N state vars updated in a
# for(;;) loop, masked to stay bounded so the analysis reaches a fixpoint and
# proves the asserts safe) — the same shape as bench.c, parameterised by N. This
# faithfully scales goblint's signature #13733 behaviour: huge minor-GC
# allocation churn with a small live set (the octagon domain is O(N^2), so wall
# and allocation grow super-linearly). Measured 5.5.0 / Ryzen 9 9950X: N=100
# ~4.3s/3.8G alloc-words/77MB, 165 ~16s/14G/120MB, 240 ~47s/40G/186MB (minor GC
# 15k->151k, major 41->97, top_heap 5.9->19.5M — live set grows too). Files are
# gitignored; generated once (deterministic in N).
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

# 3. Emit a wrapper that runs Goblint on the SV-COMP workload.  apron's shared
#    libs live in the prefix, so the wrapper puts them on the dynamic loader
#    path (the OCaml side is statically linked, but apron's C .so are dlopened).
#    The analysed C file is chosen by output name: goblint_gen_<rung> gets the
#    matching generated state machine; the frozen `goblint` program keeps bench.c.
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
export CAML_LD_LIBRARY_PATH="${APRON_PREFIX}/lib/stublibs:${APRON_PREFIX}/lib/apron"
export LD_LIBRARY_PATH="${APRON_PREFIX}/lib/apron\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
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
