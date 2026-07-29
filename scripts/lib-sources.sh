#!/usr/bin/env bash
# lib-sources.sh — read pinned versions from sources.yml and clone git sources at
# their pinned commit. Source this file; don't execute it.
#
# Why: six vendored git sources (ppxlib, lwt, merlin, js_of_ocaml, pplacer, mcl)
# used to be cloned at a *branch HEAD*, so a cold `make setup` picked up whatever
# upstream happened to have that day — silently changing the vendored sources, the
# benchmark binaries built from them, and therefore the measurements. Two of them
# had already drifted from the validated tree by the time this was written (ppxlib
# by 7 weeks, lwt by 3 months), and one branch had been deleted upstream
# altogether, which broke a cold setup outright.
#
# Bumping a pin is now a one-line edit to sources.yml: it shows up in review, and
# CI rebuilds and re-runs everything against it. That is the whole point.

_SOURCES_YML="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sources.yml"

# src_field <top-level key> <field> — print one field from sources.yml.
#
# Deliberately dependency-free rather than PyYAML: sources.yml is a flat two-level
# map with one `key: value` per line, so awk is enough, and setup keeps working on
# a machine that has nothing but bash, git, curl and a compiler.
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

# clone_pinned <sources.yml key> <destination dir>
#
# Idempotent: if the destination is already at the pinned commit this does
# nothing, so setup stays re-runnable. If the pin has moved — or the checkout is a
# pre-pin one with no .git — it re-clones. The .git dir is kept on purpose: it is
# how you find out what you actually have (`git -C <dir> rev-parse HEAD`) and how
# this function decides whether to re-clone. The old scripts deleted it, which is
# why recovering the pins in the first place meant reverse-engineering tree hashes.
clone_pinned() {
  local key="$1" dest="$2"
  local repo commit branch got
  repo="$(src_field "$key" repo)"
  commit="$(src_field "$key" commit)"
  branch="$(src_field "$key" branch)"

  if [ -z "${repo}" ] || [ -z "${commit}" ]; then
    echo "ERROR: sources.yml has no repo/commit for '${key}'" >&2
    return 1
  fi

  if [ "$(git -C "${dest}" rev-parse HEAD 2>/dev/null)" = "${commit}" ]; then
    echo "  ${key}: already at pinned ${commit:0:12}. Skipping."
    return 0
  fi

  echo "  ${key}: cloning ${commit:0:12} (${branch:-detached})..."
  rm -rf "${dest}"
  mkdir -p "${dest}"
  git -C "${dest}" init -q
  git -C "${dest}" remote add origin "${repo}"
  # Three ways to land on the pinned commit, cheapest first:
  #   1. shallow fetch of the commit itself — GitHub allows this;
  #   2. shallow fetch of the branch/tag it came from, then verify we got the
  #      pinned commit — for hosts that refuse a bare commit (GitLab by default).
  #      Still pinned: if the ref has moved, the verify below fails loudly;
  #   3. full clone — last resort, correct but slow.
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

  got="$(git -C "${dest}" rev-parse HEAD 2>/dev/null)"
  if [ "${got}" != "${commit}" ]; then
    echo "ERROR: ${key} checked out ${got:-nothing}, expected ${commit}" >&2
    return 1
  fi
}
