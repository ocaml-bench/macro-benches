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

# 3. Emit a wrapper that runs Goblint on the SV-COMP workload.  apron's shared
#    libs live in the prefix, so the wrapper puts them on the dynamic loader
#    path (the OCaml side is statically linked, but apron's C .so are dlopened).
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
  "${BENCH_DIR}/bench.c" "\$@"
WRAPPER
chmod +x "${OUT}"

echo "goblint built: ${OUT}"
