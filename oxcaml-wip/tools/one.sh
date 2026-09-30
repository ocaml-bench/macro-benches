#!/usr/bin/env bash
# one.sh PROG... : OxCaml build of the given programs, print distinct errors
cd "$(dirname "$0")/../.."
L=${L:?scratch dir}; mkdir -p $L/two
rm -rf ci-logs/two-one
PATH=${OXBIN:-$HOME/.opam/running-ng-oxcaml-trunk/bin}:$PATH RUNNING_OCAML_RUNTIME_NAME=two-ox LOG_DIR=$PWD/ci-logs/two-one ONLY="$*" timeout 5000 bash scripts/ci-build-all.sh > $L/two/one.log 2>&1
echo "ok: $(grep -E ' ok ' $L/two/one.log | awk '{print $1}' | tr '\n' ' ')"
python3 "$(dirname "$0")/ox_errors.py" ci-logs/two-one | grep -v '^$' | cut -c1-220 | head -${N:-40}
for f in ci-logs/two-one/*.log; do grep -q '^File "' $f || grep -q 'ok' <<<"$(grep -E "^$(basename $f .log) " $L/two/one.log)" || { echo "NOFILE: $f"; grep -iE 'error' $f | head -5; }; done
