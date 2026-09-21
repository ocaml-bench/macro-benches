#!/usr/bin/env bash
# Build every program in benchmarks/manifest.yml. Runs everything before
# failing (a hermeticity break usually hits several benchmarks), prints a result
# table (also to $GITHUB_STEP_SUMMARY), exits 1 if any build failed.
#
# Env: RUNNING_OCAML_RUNTIME_NAME  runtime tag, selects _build-<tag> (default ci)
#      LOG_DIR                     per-program logs (default ci-logs/build)
#      ONLY                        space-separated program names (default all)
set -uo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_TAG="${RUNNING_OCAML_RUNTIME_NAME:-ci}"
LOG_DIR="${LOG_DIR:-${MONOREPO_DIR}/ci-logs/build}"
ONLY="${ONLY:-}"

mkdir -p "${LOG_DIR}"

echo "=== Building all benchmarks (runtime tag: ${RUNTIME_TAG}) ==="
echo "monorepo:  ${MONOREPO_DIR}"
echo "build dir: ${MONOREPO_DIR}/_build-${RUNTIME_TAG}"
echo "compiler:  $(ocamlopt -version 2>/dev/null || echo '??') ($(command -v ocamlopt || echo 'ocamlopt not on PATH'))"
echo "dune:      $(dune --version 2>/dev/null || echo '??')"
echo ""

failed=0
count=0
results=()

while IFS=$'\t' read -r name tool script; do
  [ -n "${name}" ] || continue
  if [ -n "${ONLY}" ] && [[ " ${ONLY} " != *" ${name} "* ]]; then continue; fi

  bench_dir="${MONOREPO_DIR}/benchmarks/${tool}"
  out="${bench_dir}/${name}-${RUNTIME_TAG}"
  log="${LOG_DIR}/${name}.log"
  count=$((count + 1))

  # A stale wrapper exec'ing a missing .exe would make running-ng skip the
  # rebuild and die at run time with 127.
  rm -f "${out}"

  printf '%-24s ' "${name}"
  start=${SECONDS}
  env RUNNING_OCAML_BENCH_DIR="${bench_dir}" \
      RUNNING_OCAML_OUTPUT="${out}" \
      RUNNING_OCAML_RUNTIME_NAME="${RUNTIME_TAG}" \
      bash "${bench_dir}/${script}" > "${log}" 2>&1
  rc=$?
  elapsed=$((SECONDS - start))

  if [ ${rc} -eq 0 ] && [ -x "${out}" ]; then
    printf 'ok      %4ds\n' "${elapsed}"
    results+=("ok|${name}|${elapsed}|")
  elif [ ${rc} -eq 0 ]; then
    printf 'FAILED  %4ds  (script succeeded but produced no executable at %s)\n' \
      "${elapsed}" "${out#"${MONOREPO_DIR}/"}"
    results+=("FAILED|${name}|${elapsed}|no executable produced")
    failed=$((failed + 1))
  else
    printf 'FAILED  %4ds  (exit %d, see %s)\n' "${elapsed}" "${rc}" "${log#"${MONOREPO_DIR}/"}"
    # `|` is the field separator for the summary rows, so strip it from log text.
    results+=("FAILED|${name}|${elapsed}|exit ${rc}: $(tail -3 "${log}" | tr '\n|' ' /' | cut -c1-160)")
    failed=$((failed + 1))
  fi
done < <(python3 "${MONOREPO_DIR}/scripts/ci-manifest.py" list | cut -f1,2,3)

echo ""
echo "=== ${count} programs, $((count - failed)) built, ${failed} failed ==="

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Build — $((count - failed))/${count} programs"
    echo ""
    echo "| program | result | build time | detail |"
    echo "|---|---|---:|---|"
    for r in "${results[@]}"; do
      IFS='|' read -r status name elapsed detail <<< "${r}"
      icon=$([ "${status}" = "ok" ] && echo ":white_check_mark:" || echo ":x:")
      echo "| \`${name}\` | ${icon} ${status} | ${elapsed}s | ${detail} |"
    done
  } >> "${GITHUB_STEP_SUMMARY}"
fi

[ ${failed} -eq 0 ] || exit 1
