#!/usr/bin/env bash
# Shell helpers that behave the same on GNU and BSD userland. Sourced by
# setup-monorepo.sh and the vendor-*.sh scripts. Each helper works on Linux
# too and must keep the Linux behaviour unchanged.
#
# FreeBSD (pkg, /usr/local) and macOS (Homebrew) install where the system clang
# does not search, so a vendored C stub fails with "fatal error:
# 'gsl/gsl_vector.h' file not found". Appended (a caller's own value keeps
# priority) and idempotent (vendor scripts inherit the exports and source this
# file again).
case "$(uname -s)" in
    FreeBSD) _localbase="${LOCALBASE:-$(sysctl -n user.localbase 2>/dev/null || echo /usr/local)}" ;;
    Darwin)  _localbase="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null || echo /opt/homebrew)}" ;;
    *)       _localbase= ;;
esac
if [ -n "${_localbase}" ]; then
    _append_path_once() {      # <var name> <dir>
        local _cur="${!1:-}"
        case ":${_cur}:" in
            *":$2:"*) return 0 ;;
        esac
        export "$1=${_cur:+${_cur}:}$2"
    }
    _append_path_once C_INCLUDE_PATH     "${_localbase}/include"
    _append_path_once CPLUS_INCLUDE_PATH "${_localbase}/include"
    _append_path_once LIBRARY_PATH       "${_localbase}/lib"
    # Homebrew's openblas is keg-only: owl finds it through pkg-config.
    if [ -d "${_localbase}/opt/openblas/lib/pkgconfig" ]; then
        _append_path_once PKG_CONFIG_PATH "${_localbase}/opt/openblas/lib/pkgconfig"
    fi
    unset -f _append_path_once
fi
unset _localbase

# PCRE 1 is built by scripts/vendor-pcre.sh; pcre-ocaml finds it through pkg-config.
_pcre_pc="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vendor/.pcre-prefix/lib/pkgconfig"
case ":${PKG_CONFIG_PATH:-}:" in
    *":${_pcre_pc}:"*) ;;
    *) export PKG_CONFIG_PATH="${_pcre_pc}${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}" ;;
esac
unset _pcre_pc

# macOS: Homebrew's gcc (goblint's CIL needs it) is built against the newest
# Command Line Tools SDK; with older CLT and a newer Xcode it cannot find
# stdio.h. Point every compiler at the SDK xcrun selects.
if [ "$(uname -s)" = Darwin ] && [ -z "${SDKROOT:-}" ] && command -v xcrun >/dev/null 2>&1; then
    SDKROOT="$(xcrun --show-sdk-path 2>/dev/null)" && export SDKROOT
fi

# The <regex> helpers pass it to awk (ERE only): write a literal parenthesis as
# `[(]`, not `\(`, which awk reads as a group.

# gnu_make: the name of GNU make. camlidl's Makefile uses GNU conditionals that
# FreeBSD's bmake rejects (`make: "lib/Makefile" line 27: Invalid line "ifneq ..."`).
# Only use it for a Makefile that actually needs GNU make.
gnu_make() {
    if command -v gmake >/dev/null 2>&1; then
        printf 'gmake'
    else
        printf 'make'
    fi
}

# sed_i <sed args...> <file>: in-place sed without -i (GNU and BSD disagree on
# its argument). Copying back, not mv, preserves the file's mode and inode.
sed_i() {
    local file="${!#}"                       # last argument
    local args=("${@:1:$#-1}")               # everything before it
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/sed_i.XXXXXX")" || return 1
    if sed "${args[@]}" "$file" > "$tmp"; then
        cat "$tmp" > "$file"
        rm -f "$tmp"
    else
        rm -f "$tmp"
        return 1
    fi
}

# insert_after <file> <regex> <text...>: append the lines after every matching
# line. Replaces GNU `sed -i '/re/a text'`; each argument is one line, unescaped.
insert_after() {
    local file="$1" regex="$2"
    shift 2
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/insert_after.XXXXXX")" || return 1
    awk -v re="$regex" -v n="$#" 'BEGIN { for (i = 1; i < ARGC - 1; i++) { add[i] = ARGV[i]; ARGV[i] = "" } }
        { print }
        $0 ~ re { for (i = 1; i <= n; i++) print add[i] }
    ' "$@" "$file" > "$tmp" && cat "$tmp" > "$file"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# insert_after_offset <file> <regex> <offset> <text...>: append after the line
# <offset> lines below a match (0 = the match). Replaces GNU `sed '/re/{N;N;N; a text}'`.
insert_after_offset() {
    local file="$1" regex="$2" offset="$3"
    shift 3
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/insert_off.XXXXXX")" || return 1
    awk -v re="$regex" -v off="$offset" -v n="$#" 'BEGIN { for (i = 1; i < ARGC - 1; i++) { add[i] = ARGV[i]; ARGV[i] = "" } }
        { print
          if (!target && $0 ~ re) target = FNR + off
          if (target && FNR >= target) { for (i = 1; i <= n; i++) print add[i]; target = 0 }
        }
    ' "$@" "$file" > "$tmp" && cat "$tmp" > "$file"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# insert_at_line <file> <lineno> <text...>: append after line <lineno>.
# Replaces GNU `sed -i '1a text'`.
insert_at_line() {
    local file="$1" lineno="$2"
    shift 2
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/insert_at.XXXXXX")" || return 1
    awk -v ln="$lineno" -v n="$#" 'BEGIN { for (i = 1; i < ARGC - 1; i++) { add[i] = ARGV[i]; ARGV[i] = "" } }
        { print; if (FNR == ln) for (i = 1; i <= n; i++) print add[i] }
    ' "$@" "$file" > "$tmp" && cat "$tmp" > "$file"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# delete_first_match <file> <regex>: delete only the first matching line.
# Replaces GNU `sed -i '0,/re/{/re/d}'`, whose line-0 range BSD sed rejects.
delete_first_match() {
    local file="$1" regex="$2"
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/del_first.XXXXXX")" || return 1
    awk -v re="$regex" '!done && $0 ~ re { done = 1; next } { print }' \
        "$file" > "$tmp" && cat "$tmp" > "$file"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# checksum <file>: lowercase hex MD5 via md5sum or BSD md5 (-q drops its
# "MD5 (file) = " prefix).
checksum() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | cut -d' ' -f1
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q "$1"
    else
        echo "ERROR: neither md5sum nor md5 found; cannot verify downloads" >&2
        return 1
    fi
}

# ncpu: usable parallelism, defaulting to 1 rather than guessing high.
ncpu() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 1
    fi
}

# Building several runtimes at once in one tree (running-ng builds in parallel
# when the tree has .parallel-builds): a second dune process on a build dir
# fails, and infer hides duniverse packages while it builds. So every dune call
# holds its build dir's lock and the tree lock shared; infer holds the tree lock
# exclusively. Locks are flock(2) through python3, which FreeBSD's base system
# has no command for; one taken on a shell fd stays held until the fd is closed.
_tree_lock() { printf '%s/.build-tree.lock' "${MONOREPO_DIR:?}"; }
_flock_fd() {  # <fd> sh|ex|un
    python3 -c 'import fcntl, sys
op = {"sh": fcntl.LOCK_SH, "ex": fcntl.LOCK_EX, "un": fcntl.LOCK_UN}[sys.argv[2]]
fcntl.flock(int(sys.argv[1]), op)' "$1" "$2"
}

# dune_locked <dune args...>: dune, waiting for its build dir and the tree (fds 5, 6).
dune_locked() {
    local bd="" prev="" a rc=0
    for a in "$@"; do
        [ "$prev" = "--build-dir" ] && bd="$a"
        prev="$a"
    done
    [ -n "$bd" ] || bd="${MONOREPO_DIR:?}/_build"
    exec 5>"$(_tree_lock)" 6>"$bd.lock"
    _flock_fd 5 sh
    _flock_fd 6 ex
    dune "$@" || rc=$?
    exec 5>&- 6>&-
    return $rc
}

# tree_lock_exclusive / tree_unlock: hold the tree lock alone (fd 7).
tree_lock_exclusive() { exec 7>"$(_tree_lock)"; _flock_fd 7 ex; }
tree_unlock() { exec 7>&-; }

# gen_lock <file> / gen_unlock: serialise generating shared inputs (fd 8), so a
# second runtime's build waits and then finds them complete.
gen_lock() { exec 8>"$1"; _flock_fd 8 ex; }
gen_unlock() { exec 8>&-; }

# seed_src_copy <shared> <dest>: a private copy of a shared source clone, for a
# vendor script that resets and builds in place. No-op if dest exists or the
# shared clone does not (the vendor script then clones dest itself).
seed_src_copy() {
    [ -d "$2" ] || [ ! -d "$1" ] || {
        gen_lock "$1.lock"
        [ -d "$2" ] || { cp -a "$1" "$2.tmp.$$" && mv "$2.tmp.$$" "$2"; }
        gen_unlock
    }
}
