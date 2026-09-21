#!/usr/bin/env bash
# frama-c.build.sh: statically linked Frama-C kernel + EVA (see benchmarks/frama-c/dune)
# plus a wrapper. Wrapper argv.1: `t` (zlib t.c, fixed fast run, not a rung);
# `sqlite [PREC]` (sqlite3.c amalgamation, the ocaml#11733 hashconsing stress;
# PREC is -eva-precision 0..11, the input-size axis, since -eva-slevel measured
# flat 0..500); anything else is passed straight to EVA.
# The uninstalled binary needs -no-autoload-plugins (EVA is statically
# registered) and DUNE_DIR_LOCATIONS for the frama-c share site, or it crashes
# in System_config (List.hd of empty site). assigns:missing is downgraded to
# feedback so sqlite's spec-less libc calls don't abort the analysis.
set -euo pipefail

# running-ng runs this script directly, without setup-monorepo.sh's environment;
# lib-portable.sh supplies the FreeBSD LOCALBASE exports (else a vendored C stub
# fails with "'event.h' file not found"). scripts/tests/test-build-scripts-portable.sh enforces this.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib-portable.sh"

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
    # input size = EVA precision (-eva-precision).  Level from \$2, else
    # FRAMAC_EVA_PRECISION, else 0 (≈ legacy -eva-slevel 0 behaviour).
    PREC="\${2:-\${FRAMAC_EVA_PRECISION:-0}}"
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
    # false. Measured effect on this analysis: bUseLongDouble drops to 0 and one
    # alarm of 87 disappears (the signed-overflow alarm inside the long-double
    # detection code itself) -- the other 12000+ log lines are identical.
    #
    # This define alone is NOT sufficient at low -eva-precision. The gate folds
    # to 0 only when EVA can keep the bUseLongDouble global precise; at
    # -eva-precision 0/1 (the small rung) it widens the global to {0;1}, analyses
    # BOTH arms, and still hits the 1.0e+119L long-double *literals* -> the same
    # exit-3 abort, on every host. (It reproduces locally too; CI just surfaced it
    # first because only the small rung, precision 0, is flagged ci_run.) So the
    # three bUseLongDouble branches in sqlite3.c are additionally neutralised with
    # \`if( 0 && ... )\` (grep "no long double builtins"), forcing EVA down the
    # portable non-long-double path at every precision. That is a benign SQLite
    # config (the path used wherever high-precision long double is unavailable)
    # and irrelevant to what this benchmark measures.
    exec "${REAL_EXE}" -no-autoload-plugins \\
      -eva -eva-no-results -eva-precision "\$PREC" -main main \\
      -eva-warn-key assigns:missing=feedback \\
      -cpp-extra-args="-DLONGDOUBLE_TYPE=double -D'__has_extension(x)=1'" \\
      "${BENCH_DIR}/sqlite_driver.c" "${BENCH_DIR}/sqlite3.c" ;;
  *)
    exec "${REAL_EXE}" -no-autoload-plugins "\$@" ;;
esac
WRAPPER
chmod +x "${OUT}"

echo "frama-c EVA built: ${OUT}"
