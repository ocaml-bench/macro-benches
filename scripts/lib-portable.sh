#!/usr/bin/env bash
# Shell helpers that behave the same on GNU and BSD userland. Sourced by
# setup-monorepo.sh and the vendor-*.sh scripts. Each helper works on Linux
# too and must keep the Linux behaviour unchanged.
#
# FreeBSD: pkg installs under /usr/local, which base clang does not search, so
# a vendored C stub fails with "fatal error: 'gsl/gsl_vector.h' file not found".
# Appended (a caller's own value keeps priority) and idempotent (vendor scripts
# inherit the exports and source this file again).
if [ "$(uname -s)" = "FreeBSD" ]; then
    _localbase="${LOCALBASE:-$(sysctl -n user.localbase 2>/dev/null || echo /usr/local)}"
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
    unset _localbase
    unset -f _append_path_once
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
