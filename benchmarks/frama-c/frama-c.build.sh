#!/usr/bin/env bash
# frama-c.build.sh — build the Frama-C EVA benchmark from the monorepo.
#
# Builds a standalone executable that statically links the Frama-C kernel
# + the EVA (value/abstract-interpretation) plugin (see benchmarks/frama-c/dune),
# then emits a wrapper that runs EVA on a C workload.
#
# The wrapper sets two things the static, uninstalled build needs:
#   * -no-autoload-plugins : EVA is statically registered, so the dune-site
#       plugin loader must NOT run (there is no plugin site to discover).
#   * DUNE_DIR_LOCATIONS   : points Frama-C's dune-site "share"/"lib" sites
#       at the vendored source tree (frama-c:share:<root> resolves to
#       <root>/share, which holds machdeps/, libc/, ...).  Without this the
#       uninstalled binary crashes in System_config (List.hd of empty site).
#
# Two workloads, selected by the wrapper's first argument:
#   t       (default) : EVA on t.c (zlib, ~17.5k lines) — abstract-interp
#                       focused, ~6s.
#   sqlite            : EVA on the SQLite amalgamation (sqlite3.c, ~258k
#                       lines) via a small driver — stresses the weak/
#                       ephemeron hashconsing of a huge CIL AST + EVA state
#                       (the OCaml-5 regression of ocaml#11733), ~7s / 460MB
#                       at -eva-slevel 0; raise slevel to push wall+RSS.
# Any other arguments are passed straight through to the EVA executable.
#
# assigns:missing is downgraded from error→feedback for the sqlite run:
# the amalgamation calls spec-less libc/OS functions that would otherwise
# abort EVA; we want it to keep analysing, not prove soundness.
set -euo pipefail

BENCH_DIR="${RUNNING_OCAML_BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT="${RUNNING_OCAML_OUTPUT:-${BENCH_DIR}/frama-c-${RUNNING_OCAML_RUNTIME_NAME:-runtime}}"
MONOREPO_DIR="$(cd "${BENCH_DIR}/../.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-default}"
BUILD_DIR="${MONOREPO_DIR}/_build-${RUNTIME_TAG//[^a-zA-Z0-9._-]/_}"

echo "Building frama-c EVA (monorepo) for runtime: ${RUNTIME_TAG}"

unset OPAM_SWITCH_PREFIX OCAMLTOP_INCLUDE_PATH CAML_LD_LIBRARY_PATH OCAMLLIB
export OCAMLPATH=""

dune build --root "${MONOREPO_DIR}" --build-dir "${BUILD_DIR}" \
  --profile release \
  benchmarks/frama-c/frama_c_eva.exe

REAL_EXE="${BUILD_DIR}/default/benchmarks/frama-c/frama_c_eva.exe"
SHARE_ROOT="${MONOREPO_DIR}/vendor/frama-c"

mkdir -p "$(dirname "${OUT}")"
cat > "${OUT}" << WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export DUNE_DIR_LOCATIONS="frama-c:share:${SHARE_ROOT}:frama-c:libexec:${SHARE_ROOT}"
SLEVEL="\${FRAMAC_EVA_SLEVEL:-100}"
case "\${1:-t}" in
  t)
    exec "${REAL_EXE}" -no-autoload-plugins \\
      -eva -eva-no-results -eva-slevel "\$SLEVEL" "${BENCH_DIR}/t.c" ;;
  sqlite)
    # Two defines pin the *analysed program*, which otherwise depends on the host
    # gcc. Frama-C preprocesses with \`gcc -E -undef -imacros __fc_builtin_macros.h\`,
    # so __GNUC__ is stripped and sqlite3.c's GCC_VERSION is 0 on every host. Its
    # atomics gate is therefore decided entirely by the second half of
    #   #if GCC_VERSION>=4007000 || __has_extension(c_atomic)
    # and sqlite3.c self-guards \`#ifndef __has_extension -> define it to 0\`. So on
    # gcc >= 14 (which predefines __has_extension) EVA analyses AtomicLoad as an
    # undeclared __atomic_load_n -- cheap and imprecise -- while on gcc 13 it
    # analyses the real volatile/mutex code, an enormously bigger state space: the
    # same benchmark took 7s here and blew past a 600s limit on a gcc 13.3 runner.
    # -D__has_extension(x)=1 forces the intrinsics path everywhere, so every host
    # analyses what the benchmark was characterised on. (Frama-C already passes
    # -Wno-builtin-macro-redefined, so redefining it on gcc >= 14 is quiet, and
    # nothing else in sqlite3.c or Frama-C's libc uses __has_extension.) The inner
    # single quotes matter: Frama-C runs the preprocessor through a shell, so an
    # unquoted \`(\` aborts with \`sh: Syntax error: "(" unexpected\`.
    #
    # -DLONGDOUBLE_TYPE=double: sqlite3.c gates its long-double code at runtime on
    # \`sqlite3Config.bUseLongDouble = sizeof(LONGDOUBLE_TYPE)>8\`. Where that is
    # true, EVA walks into the branch and Frama-C 32.1 aborts on an unimplemented
    # feature ("Builtins for long double type"), exit 3. SQLite documents
    # LONGDOUBLE_TYPE as an override, and setting it to double makes the gate
    # false on every host. Measured effect on this analysis: bUseLongDouble drops
    # to 0 and one alarm of 87 disappears (the signed-overflow alarm inside the
    # long-double detection code itself) -- the other 12000+ log lines are
    # identical, because the branch was never reached on a host where the gate was
    # already false.
    exec "${REAL_EXE}" -no-autoload-plugins \\
      -eva -eva-no-results -eva-slevel "\${FRAMAC_EVA_SLEVEL:-0}" -main main \\
      -eva-warn-key assigns:missing=feedback \\
      -cpp-extra-args="-DLONGDOUBLE_TYPE=double -D'__has_extension(x)=1'" \\
      "${BENCH_DIR}/sqlite_driver.c" "${BENCH_DIR}/sqlite3.c" ;;
  *)
    exec "${REAL_EXE}" -no-autoload-plugins "\$@" ;;
esac
WRAPPER
chmod +x "${OUT}"

echo "frama-c EVA built: ${OUT}"
