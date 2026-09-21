#!/usr/bin/env bash
# Read pinned versions from sources.yml and clone git sources at their pinned
# commit. Source this file; don't execute it. Bumping a pin is a one-line edit
# to sources.yml.

# Sourced here so every vendor-*.sh gets the GNU/BSD-portable helpers.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-portable.sh"

_SOURCES_YML="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sources.yml"

# src_field <top-level key> <field>: print one field from sources.yml.
# awk rather than PyYAML so setup needs nothing but bash, git, curl and a compiler.
src_field() {
  awk -v key="$1:" -v field="$2:" '
    $1 == key        { in_block = 1; next }
    /^[^[:space:]#]/ { in_block = 0 }
    in_block && $1 == field {
      sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$_SOURCES_YML"
}

# _peel_commit <dir> <sha>: the commit <sha> denotes. A pin copied from
# `git ls-remote` may be an annotated tag object, whose checkout lands on the
# commit it points at. Prints <sha> unchanged when the object is not in <dir>,
# so a real mismatch still fails.
_peel_commit() {
  git -C "$1" rev-parse -q --verify "$2^{commit}" 2>/dev/null || printf '%s\n' "$2"
}

# clone_pinned <sources.yml key> <destination dir>
# No-op when dest is already at the pin, re-clones otherwise. .git is kept so
# the pin can be checked (`git -C <dir> rev-parse HEAD`).
clone_pinned() {
  local key="$1" dest="$2"
  local repo commit branch got want
  repo="$(src_field "$key" repo)"
  commit="$(src_field "$key" commit)"
  branch="$(src_field "$key" branch)"

  if [ -z "${repo}" ] || [ -z "${commit}" ]; then
    echo "ERROR: sources.yml has no repo/commit for '${key}'" >&2
    return 1
  fi

  # `|| true`: on a first clone `git -C` exits 128, fatal under callers' `set -e`.
  got="$(git -C "${dest}" rev-parse HEAD 2>/dev/null || true)"
  if [ -n "${got}" ] && [ "${got}" = "$(_peel_commit "${dest}" "${commit}")" ]; then
    echo "  ${key}: already at pinned ${commit:0:12}. Skipping."
    return 0
  fi

  echo "  ${key}: cloning ${commit:0:12} (${branch:-detached})..."
  rm -rf "${dest}"
  mkdir -p "${dest}"
  git -C "${dest}" init -q
  git -C "${dest}" remote add origin "${repo}"
  # Cheapest first: fetch the commit (GitHub allows it), else shallow-fetch the
  # branch/tag (GitLab refuses bare commits; verified below), else full clone.
  if git -C "${dest}" fetch -q --depth 1 origin "${commit}" 2>/dev/null; then
    git -C "${dest}" checkout -q --detach FETCH_HEAD
  elif [ -n "${branch}" ] && git -C "${dest}" fetch -q --depth 1 origin "${branch}" 2>/dev/null; then
    echo "    (host refused fetch-by-commit; fetched ${branch} shallow instead)"
    git -C "${dest}" checkout -q --detach FETCH_HEAD
  else
    echo "    (shallow fetch refused; falling back to a full clone)"
    rm -rf "${dest}"
    git clone -q "${repo}" "${dest}"
    git -C "${dest}" checkout -q --detach "${commit}"
  fi

  # Compare against the peeled pin: an annotated-tag pin is still immutable.
  want="$(_peel_commit "${dest}" "${commit}")"
  if [ "${want}" != "${commit}" ]; then
    echo "    (pin ${commit:0:12} is an annotated tag object; it peels to commit ${want:0:12})"
  fi
  got="$(git -C "${dest}" rev-parse HEAD 2>/dev/null || true)"
  if [ "${got}" != "${want}" ]; then
    echo "ERROR: ${key} checked out ${got:-nothing}, expected ${want}" >&2
    return 1
  fi
}
