"""Rewrite upstream-ppxlib constructor patterns to OxCaml ppxlib's shapes.

Usage: ox_ast.py FILE...   (edits in place; meant for *.oxcaml.ml variants)
Handles pattern positions only: Ptyp_var/Ptyp_any (jkind), Ptyp_tuple and
Pcstr_tuple (labelled / constructor_argument lists), Ptyp_poly, Ptyp_alias,
and pexp_function_cases -> pexp_function.
"""
import re
import sys


def bind_after_arrow(s, m, stmt):
    j = s.index("->", m.end()) + 2
    return s[:j] + " " + stmt + s[j:]


def rewrite(s):
    s = s.replace("pexp_function_cases", "pexp_function")
    s = re.sub(r"\bPtyp_var (\w+)(?=\s*[;}\)]|\s*->|\s+when\b)", r"Ptyp_var (\1, _)", s)
    s = re.sub(r"\bPtyp_any(?=\s*[;}\)]|\s*->|\s*\|)", r"Ptyp_any _", s)
    s = re.sub(r"\bPtyp_alias \((\w+), (\w+)\)", r"Ptyp_alias (\1, Some \2, _)", s)
    rules = [
        (r"\bPtyp_tuple\s*\(?(\w+)\)?(?=\s*[;}\]\)])", "Ptyp_tuple {v}", "List.map snd {v}"),
        (r"\bPcstr_tuple\s*\(?(\w+)\)?(?=\s*[;}\]\)]|\s*->|\s*when\b)", "Pcstr_tuple {v}",
         "List.map (fun a -> a.Ppxlib.pca_type) {v}"),
        (r"\bPtyp_poly \((\w+), (\w+)\)", "Ptyp_poly ({v}, {w})", "List.map fst {v}"),
    ]
    for pat, repl, conv in rules:
        pos = 0
        while True:
            m = re.compile(pat).search(s, pos)
            if not m:
                break
            v = m.group(1)
            if v == "_" or v.startswith("ox__"):
                pos = m.end()
                continue
            w = m.group(2) if m.re.groups > 1 else ""
            new = repl.format(v="ox__" + v, w=w)
            s = s[:m.start()] + new + s[m.end():]
            m2 = re.compile(re.escape(new)).search(s, m.start())
            s = bind_after_arrow(s, m2, f"let {v} = {conv.format(v='ox__' + v)} in")
            pos = m.start() + len(new)
    return s


for f in sys.argv[1:]:
    src = open(f).read()
    out = rewrite(src)
    if out != src:
        open(f, "w").write(out)
        print("rewrote", f)
