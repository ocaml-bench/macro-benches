#!/usr/bin/env bash
# Run every program in benchmarks/manifest.yml once, with its manifest args,
# from a fresh scratch cwd. A correctness/hermeticity gate, not a measurement:
# no olly, no perf, no pinning. Runs everything before failing; exits 1 if any
# program exited unexpectedly or timed out.
#
# Env: RUNNING_OCAML_RUNTIME_NAME  runtime tag matching the build (default ci)
#      LOG_DIR                     per-program logs (default ci-logs/run)
#      ONLY                        space-separated program names (default all)
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

  # ${SCRATCH} in manifest args means this program's scratch cwd; substitute
  # before the word split below.
  args="${args//\$\{SCRATCH\}/${cwd}}"

  # Manifest args are plain paths and numbers; word splitting is intended.
  read -ra argv <<< "${args}"

  start=${SECONDS}
  ( cd "${cwd}" && timeout --kill-after=30s "${timeout_s}" "${exe}" "${argv[@]}" ) \
    > "${log}" 2>&1
  rc=$?
  elapsed=$((SECONDS - start))

  case ${rc} in
    "${expected_exit}")
      # Some programs exit non-zero by design (alt-ergo's --timelimit dies by
      # SIGALRM), declared as expected_exit.
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
