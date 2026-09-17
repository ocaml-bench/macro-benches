#!/usr/bin/env bash
# lib-portable.sh — shell helpers that behave the same on GNU and BSD userland.
#
# Sourced by setup-monorepo.sh and the vendor-*.sh scripts. Every helper here
# exists because the obvious GNU spelling silently differs or outright fails on
# FreeBSD and macOS:
#
#   sed -i          BSD sed requires an argument to -i; GNU forbids one.
#   sed '0,/re/'    GNU-only line-0 range, used to mean "first match only".
#   sed '/re/a txt' GNU one-line append; BSD wants `a\` and a newline.
#   md5sum          GNU coreutils; BSD has md5 with different output.
#   nproc           GNU coreutils; BSD has sysctl hw.ncpu.
#
# These are NOT FreeBSD-specific replacements: each works on Linux too, and
# the Linux behaviour must not change. `sed_i` in particular avoids -i
# altogether rather than switching on the platform, so there is one code path.
#
# PKG PREFIX: on FreeBSD, pkg installs headers under /usr/local/include and
# libraries under /usr/local/lib, and the base clang searches NEITHER. Its
# default list is only /usr/lib/clang/<v>/include and /usr/include, so a
# vendored C stub that includes a pkg-installed header fails with
#   fatal error: 'gsl/gsl_vector.h' file not found
# even though the package is installed. On Linux everything lands in
# /usr/include, so this cannot show up there, which is why it took a cold
# FreeBSD run to surface: it hit gsl and libevent, but it is a CLASS, not two
# libraries, and any pkg-installed header would trip it.
#
# Exported here rather than in setup-monorepo.sh so the vendor-*.sh scripts get
# it when run directly too; they all source this file. Appended, not prepended:
# a caller who set these deliberately keeps priority over us. Idempotent,
# because setup-monorepo.sh exports these and then each vendor script is a
# subprocess that inherits them AND sources this file again, which would
# otherwise grow a duplicate entry per nesting level. FreeBSD only: NetBSD and
# OpenBSD use a different prefix and neither has been tested.
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

# REGEX DIALECT: every helper below that takes a <regex> passes it to awk,
# which understands only EREs. So a literal parenthesis is `[(]`, not `\(`:
# the sed spelling `\(` reaches awk as a capture group, which happens to match
# the same text in some cases and silently not in others. Bracket forms are
# unambiguous in both dialects, so call sites use those.

# gnu_make -- the name of GNU make on this system.
#
# Not every vendored Makefile is portable. camlidl's uses GNU conditionals
# (`ifneq`/`endif`), which FreeBSD's bmake rejects outright:
#   make: "lib/Makefile" line 27: Invalid line "ifneq ..."
# That is SYNTAX, so unlike the `--quiet` flag it cannot be worked around by
# changing how make is called: it needs GNU make. FreeBSD ships it as `gmake`.
#
# On Linux `make` IS GNU make and `gmake` is usually absent, so this resolves
# to `make` there and nothing changes. Only use it for a Makefile that actually
# needs GNU make: mcl's, for instance, is portable and builds fine with bmake.
gnu_make() {
    if command -v gmake >/dev/null 2>&1; then
        printf 'gmake'
    else
        printf 'make'
    fi
}

# sed_i <sed args...> <file>
#
# In-place sed without -i. Writes to a temp file and copies back, which
# preserves the original file's mode and inode (a plain `mv` would not).
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

# insert_after <file> <regex> <text...>
#
# Append the given lines after every line matching <regex>. Replaces GNU
# `sed -i '/re/a text'`. Each argument after the regex becomes one line, so
# text containing backslashes or leading whitespace needs no escaping, which
# is the part that makes the sed spelling so awkward.
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

# insert_after_offset <file> <regex> <offset> <text...>
#
# Append after the line <offset> lines below a match, so offset 0 is the
# matching line itself. Replaces GNU `sed '/re/{N;N;N; a text}'`, where the
# Ns advance past a block before appending.
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

# insert_at_line <file> <lineno> <text...>
#
# Append after a given line number. Replaces GNU `sed -i '1a text'`.
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

# delete_first_match <file> <regex>
#
# Delete only the FIRST line matching <regex>. Replaces GNU
# `sed -i '0,/re/{/re/d}'`, whose line-0 range BSD sed rejects.
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

# checksum <file>
#
# Lowercase hex MD5, however the platform spells the tool. GNU coreutils has
# md5sum; FreeBSD and macOS have md5, whose default output is
# "MD5 (file) = hash", hence -q.
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

# ncpu — usable parallelism, defaulting to 1 rather than guessing high.
ncpu() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 1
    fi
}
