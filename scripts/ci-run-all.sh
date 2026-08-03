#!/usr/bin/env bash
# ci-run-all.sh — run every program in benchmarks/manifest.yml exactly once.
#
# This is a correctness/hermeticity gate, not a measurement: one invocation, no
# olly, no perf, no pinning, wall time reported only so an obvious blow-up is
# visible. Real numbers come from running-ng on dedicated hardware.
#
# Each program runs with its manifest args (identical to running-ng's) from a
# fresh scratch working directory, so relative outputs (menhir's `--base`,
# goblint's witness.yml) land there and not in the source tree.
#
# Like ci-build-all.sh it runs everything before failing, and exits 1 if any
# program exited non-zero or hit its timeout.
#
# Environment:
#   RUNNING_OCAML_RUNTIME_NAME  runtime tag, matching the build (default: ci)
#   LOG_DIR                     where to write per-program logs
#   ONLY                        space-separated program names to run (default: all)
set -uo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-ci}"
LOG_DIR="${LOG_DIR:-${MONOREPO_DIR}/ci-logs/run}"
ONLY="${ONLY:-}"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH}"' EXIT

mkdir -p "${LOG_DIR}"

echo "=== Running all benchmarks once (runtime tag: ${RUNTIME_TAG}) ==="
echo "scratch cwd: ${SCRATCH}"
echo ""

failed=0
count=0
results=()

while IFS=$'\t' read -r name tool timeout_s expected_exit args; do
  [ -n "${name}" ] || continue
  if [ -n "${ONLY}" ] && [[ " ${ONLY} " != *" ${name} "* ]]; then continue; fi

  exe="${MONOREPO_DIR}/benchmarks/${tool}/${name}-${RUNTIME_TAG}"
  log="${LOG_DIR}/${name}.log"
  count=$((count + 1))

  printf '%-24s ' "${name}"

  if [ ! -x "${exe}" ]; then
    printf 'SKIPPED (not built)\n'
    results+=("FAILED|${name}|0|not built")
    failed=$((failed + 1))
    continue
  fi

  cwd="${SCRATCH}/${name}"
  mkdir -p "${cwd}"

  # ${SCRATCH} in the manifest args means "this program's scratch cwd" — used by
  # the one benchmark that would otherwise write its output into the source tree.
  # Must happen before the word split below.
  args="${args//\$\{SCRATCH\}/${cwd}}"

  # Manifest args are plain paths and numbers — word splitting is what we want.
  read -ra argv <<< "${args}"

  start=${SECONDS}
  ( cd "${cwd}" && timeout --kill-after=30s "${timeout_s}" "${exe}" "${argv[@]}" ) \
    > "${log}" 2>&1
  rc=$?
  elapsed=$((SECONDS - start))

  case ${rc} in
    "${expected_exit}")
      # Most programs expect 0; a couple exit non-zero by design (alt-ergo's
      # --timelimit kills itself with SIGALRM), declared as expected_exit.
      if [ "${expected_exit}" = "0" ]; then
        printf 'ok      %4ds\n' "${elapsed}"
      else
        printf 'ok      %4ds  (exit %s, as declared)\n' "${elapsed}" "${expected_exit}"
      fi
      results+=("ok|${name}|${elapsed}|")
      ;;
    124|137)
      printf 'TIMEOUT %4ds  (limit %ss)\n' "${elapsed}" "${timeout_s}"
      results+=("TIMEOUT|${name}|${elapsed}|exceeded ${timeout_s}s limit")
      failed=$((failed + 1))
      ;;
    *)
      printf 'FAILED  %4ds  (exit %d, expected %s, see %s)\n' \
        "${elapsed}" "${rc}" "${expected_exit}" "${log#"${MONOREPO_DIR}/"}"
      # `|` is the field separator for the summary rows, so strip it from log text.
      results+=("FAILED|${name}|${elapsed}|exit ${rc} (expected ${expected_exit}): $(tail -3 "${log}" | tr '\n|' ' /' | cut -c1-160)")
      failed=$((failed + 1))
      ;;
  esac
done < <(python3 "${MONOREPO_DIR}/scripts/ci-manifest.py" list-run | cut -f1,2,4,5,6)

echo ""
echo "=== ${count} programs, $((count - failed)) ran clean, ${failed} failed ==="

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Run once — $((count - failed))/${count} programs"
    echo ""
    echo "| program | result | wall | detail |"
    echo "|---|---|---:|---|"
    for r in "${results[@]}"; do
      IFS='|' read -r status name elapsed detail <<< "${r}"
      icon=$([ "${status}" = "ok" ] && echo ":white_check_mark:" || echo ":x:")
      echo "| \`${name}\` | ${icon} ${status} | ${elapsed}s | ${detail} |"
    done
    echo ""
    echo "_Wall times are from a shared CI runner — indicative only, not measurements._"
  } >> "${GITHUB_STEP_SUMMARY}"
fi

[ ${failed} -eq 0 ] || exit 1
