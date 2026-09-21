#!/usr/bin/env bash
# Fetch the pinned Java corpus jars and merge them into one classes-only jar for
# the infer benchmark (curl + unzip + zip only, no JDK).
#
# Any new jar must survive `infer capture --generated-classes X --classpath X`
# under the vendored sawja; clojure 1.11.1 is excluded because its synthetic
# bytecode raises an uncaught Sawja_pack.Bir.Bad_stack. The class set is what
# benchmarks/infer/roots_<rung>.idx is expressed against: keep them in sync.
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${MONOREPO_DIR}/vendor/.infer-corpus"
CORPUS="${DEST}/corpus.jar"

if [ -f "${CORPUS}" ]; then
  echo "infer corpus already present: ${CORPUS} (remove to re-fetch)"
  exit 0
fi

BASE="https://repo1.maven.org/maven2"
mkdir -p "${DEST}/dl" "${DEST}/merge"

fetch () { # <maven-relative-path> <sha256>
  local rel="$1" sha="$2" f="${DEST}/dl/$(basename "$1")"
  [ -f "$f" ] || curl -fsSL -o "$f" "${BASE}/${rel}"
  echo "${sha}  ${f}" | shasum -a 256 -c - >/dev/null \
    || { echo "checksum mismatch for ${rel}" >&2; exit 1; }
  printf '%s' "$f"
}

J1=$(fetch com/google/guava/guava/27.0-jre/guava-27.0-jre.jar          63b09db6861011e7fb2481be7790c7fd4b03f0bb884b3de2ecba8823ad19bf3f)
J2=$(fetch net/bytebuddy/byte-buddy/1.12.21/byte-buddy-1.12.21.jar     f6f45c2237a7f132c16745ad2a52c4cdde58028b11ee80b09f0d422f4930d685)
J3=$(fetch org/apache/lucene/lucene-core/9.12.0/lucene-core-9.12.0.jar 6c7b774b75cd8f369e246f365a47caa54ae991cae6afa49c7f339e9921ca58a0)
J4=$(fetch org/bouncycastle/bcprov-jdk18on/1.78/bcprov-jdk18on-1.78.jar 1bf721b09758b3f55f2a5c875b6178ec6c41dddad854b0dead4b27a236f1943a)

# Classes only, flat and single-release (no META-INF/versions, no module-info),
# matching how roots_<rung>.idx was generated.
for j in "$J1" "$J2" "$J3" "$J4"; do
  ( cd "${DEST}/merge" && unzip -o -q "$j" '*.class' -x 'META-INF/*' )
done
find "${DEST}/merge" -name 'module-info.class' -delete

# -X strips extra file attributes for a reproducible archive.
( cd "${DEST}/merge" && zip -q -r -X "${CORPUS}" . )

echo "infer corpus built: ${CORPUS} ($(find "${DEST}/merge" -name '*.class' | wc -l | tr -d ' ') classes)"
