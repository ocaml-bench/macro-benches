"""Add (enabled_if COND) to every top-level dune stanza under DIR.

Usage: gate.py DIR ox|stock [--skip SUBDIR]...
  ox    -> (= %{ocaml_version} 5.4.0+ox)
  stock -> (<> %{ocaml_version} 5.4.0+ox)
Skipped subdirs are not descended into (used to leave the ox/ copy alone
when gating the stock copy). Idempotent.
"""
import os
import re
import sys

OXV = "5.4.0+ox"
GATED = {
    "library", "executable", "executables", "test", "tests", "rule", "install",
    "alias", "ocamllex", "ocamlyacc", "menhir", "copy_files",
    "copy_files#", "mdx", "foreign_library",
    "generate_sites_module", "plugin", "cxx_library",
}


def forms(s):
    """Yield (start, end) of top-level parenthesised forms."""
    i, n = 0, len(s)
    depth, start = 0, None
    while i < n:
        c = s[i]
        if c == ";":
            while i < n and s[i] != "\n":
                i += 1
            continue
        if s.startswith("#|", i):
            j = s.find("|#", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            i += 1
            while i < n and s[i] != '"':
                i += 2 if s[i] == "\\" else 1
            i += 1
            continue
        if s.startswith('{|', i):
            j = s.find('|}', i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == "(":
            if depth == 0:
                start = i
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                yield start, i + 1
        i += 1


def children(form):
    """Top-level children of a form body as (start, end) offsets into form."""
    return [(a + 1, b + 1) for a, b in forms(form[1:-1])]


def gate(form, cond):
    m = re.match(r"\(\s*([^\s()]+)", form)
    if not m or m.group(1) not in GATED:
        return form
    head = m.group(1)
    tag = f"(enabled_if {cond})"
    if tag in form:
        return form
    kids = children(form)
    # Short forms: (ocamllex a b) -> (ocamllex (modules a b) ...)
    if head in ("ocamllex", "ocamlyacc") and not kids:
        names = form[m.end():-1].split()
        return f"({head} (modules {' '.join(names)}) {tag})"
    for a, b in kids:
        k = form[a:b]
        if re.match(r"\(\s*enabled_if\b", k):
            inner = k[k.index("enabled_if") + len("enabled_if"):-1].strip()
            return form[:a] + f"(enabled_if (and {cond} {inner}))" + form[b:]
    return form[:-1].rstrip() + f"\n {tag})"


def process(path, cond):
    s = open(path).read()
    out, last = [], 0
    for a, b in forms(s):
        out.append(s[last:a])
        out.append(gate(s[a:b], cond))
        last = b
    out.append(s[last:])
    t = "".join(out)
    if t != s:
        open(path, "w").write(t)
        return True
    return False


def main():
    root, which = sys.argv[1], sys.argv[2]
    skip = set()
    args = sys.argv[3:]
    while args:
        if args[0] == "--skip":
            skip.add(os.path.normpath(os.path.join(root, args[1])))
            args = args[2:]
        else:
            sys.exit(f"bad arg {args[0]}")
    cond = f"(= %{{ocaml_version}} {OXV})" if which == "ox" else f"(<> %{{ocaml_version}} {OXV})"
    n = 0
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if os.path.normpath(os.path.join(d, x)) not in skip
                   and not x.startswith(("_build", "."))]
        if "dune" in files:
            n += process(os.path.join(d, "dune"), cond)
    print(f"{root}: gated {n} dune files ({which})")


main()
