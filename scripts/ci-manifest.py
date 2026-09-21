#!/usr/bin/env python3
"""Read benchmarks/manifest.yml for the CI scripts.

  ci-manifest.py list       one TAB-separated row per program:
                            name  tool  build_script  timeout  expected_exit  args
  ci-manifest.py list-run   same, only `ci_run: true` programs
  ci-manifest.py check      verify the manifest against the tree (build scripts,
                            case-dispatch names, input paths, docs pages, README
                            table, sources.yml pins); exits 1 listing problems

`args` is last: bash treats TAB as whitespace-IFS, so an empty middle field
would shift every later column.
"""

import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("error: PyYAML not found — install it with `python3 -m pip install pyyaml`")

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "benchmarks" / "manifest.yml"


def load():
    with MANIFEST.open() as f:
        m = yaml.safe_load(f)
    return m, m.get("default_timeout", 600), m.get("programs") or {}


def expand(args):
    # running-ng's spelling, so the two arg lists can be diffed mechanically.
    return args.replace("${RUNNING_MACRO_BENCH_DIR}", str(ROOT))


def cmd_list(ci_run_only=False):
    _, default_timeout, programs = load()
    for name, p in programs.items():
        if ci_run_only and not p.get("ci_run"):
            continue
        row = [
            name,
            p["tool"],
            p["build_script"],
            str(p.get("timeout", default_timeout)),
            str(p.get("expected_exit", 0)),
            expand(p.get("args") or ""),
        ]
        print("\t".join(row))


def dispatched_program_names(script):
    """Program names a build script's `case "${BM_NAME}"` dispatch accepts, or None.

    Only the first case block is read: later ones are deliberately partial.
    """
    text = script.read_text()
    block = re.search(r'case\s+"\$\{(?:BM_NAME|OUT_BASE)\}"\s+in(.*?)esac', text, re.S)
    if not block:
        return None
    names = set()
    for arm in re.finditer(r"^\s*([A-Za-z0-9_|]+)\)", block.group(1), re.M):
        names.update(a for a in arm.group(1).split("|") if a)
    return names or None


def check_pins():
    """sources.yml and the scripts must agree, and no script may clone a branch HEAD."""
    problems = []
    with (ROOT / "sources.yml").open() as f:
        sources = yaml.safe_load(f) or {}

    # Commits must be full 40-hex: an abbreviated or tag-shaped pin is ambiguous.
    for key, entry in sources.items():
        if not isinstance(entry, dict) or "commit" not in entry:
            continue
        commit = str(entry["commit"])
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            problems.append(
                f"sources.yml: {key}.commit is not a full 40-hex commit: {commit!r}"
            )

    for script in sorted((ROOT / "scripts").glob("*.sh")):
        text = script.read_text()
        rel = script.relative_to(ROOT)
        # Comments talk *about* these functions, so only scan actual code.
        code = "\n".join(
            l for l in text.splitlines() if not l.lstrip().startswith("#")
        )

        for key, field in re.findall(r"src_field\s+([A-Za-z0-9._-]+)\s+([a-z0-9_]+)", code):
            if key not in sources:
                problems.append(f"{rel}: src_field reads '{key}', absent from sources.yml")
            elif field not in (sources[key] or {}):
                problems.append(f"{rel}: src_field reads {key}.{field}, absent from sources.yml")
        for key in re.findall(r"clone_pinned\s+\"?([A-Za-z0-9._${}-]+)\"?", code):
            if key.startswith("$"):
                continue  # loop variable; the loop's literals are checked below
            if key not in sources:
                problems.append(f"{rel}: clone_pinned '{key}', absent from sources.yml")
            elif "commit" not in (sources[key] or {}):
                problems.append(f"{rel}: clone_pinned '{key}', which has no commit pin")

        # lib-sources.sh holds the one allowed `git clone` (the full-clone
        # fallback), so it is exempt.
        if script.name == "lib-sources.sh":
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if re.search(r"^\s*[^#]*\bgit clone\b", line):
                problems.append(
                    f"{rel}:{i}: direct `git clone` — use clone_pinned <sources.yml key> "
                    f"so the commit is pinned and a bump shows up in review"
                )
    return problems


def cmd_check():
    m, _, programs = load()
    disabled = m.get("disabled") or {}
    problems = []

    # 1. Every program's tool dir and build script exist.
    claimed = {}
    for name, p in programs.items():
        tool_dir = ROOT / "benchmarks" / p["tool"]
        script = tool_dir / p["build_script"]
        if not tool_dir.is_dir():
            problems.append(f"{name}: tool dir not found: benchmarks/{p['tool']}")
        elif not script.is_file():
            problems.append(f"{name}: build script not found: {script.relative_to(ROOT)}")
        claimed.setdefault(script.resolve(), set()).add(name)

    for tool, d in disabled.items():
        claimed.setdefault((ROOT / "benchmarks" / tool / d["build_script"]).resolve(), set())

    # 2. Every build script in the tree is accounted for: catches a new benchmark
    #    with no manifest entry.
    scripts = sorted((ROOT / "benchmarks").glob("*/*.build.sh"))
    for script in scripts:
        if script.resolve() not in claimed:
            problems.append(
                f"{script.relative_to(ROOT)} is not referenced by any program in "
                f"benchmarks/manifest.yml (add a program entry, or list the tool "
                f"under `disabled:` with a reason)"
            )

    # 3. Name-dispatching scripts must accept exactly the claimed programs: catches
    #    a new program on an existing tool, where (2) stays quiet.
    for script in scripts:
        declared = dispatched_program_names(script)
        if declared is None:
            continue
        listed = claimed.get(script.resolve(), set())
        if not listed and script.resolve() in claimed:
            continue  # disabled tool, nothing to compare
        rel = script.relative_to(ROOT)
        for missing in sorted(declared - listed):
            problems.append(
                f"{rel} builds `{missing}` but benchmarks/manifest.yml does not "
                f"list it — add it (or drop it from the script's case block)"
            )
        for extra in sorted(listed - declared):
            problems.append(
                f"manifest lists `{extra}` for {rel}, but that script's case block "
                f"does not accept the name — it would fail with 'Unknown benchmark'"
            )

    # 4. In-tree input files named in args must exist; generated inputs opt out.
    for name, p in programs.items():
        if p.get("inputs_generated"):
            continue
        for token in (p.get("args") or "").split():
            if not token.startswith("${RUNNING_MACRO_BENCH_DIR}/"):
                continue
            path = Path(expand(token))
            if not path.exists():
                problems.append(
                    f"{name}: input not found: {token} "
                    f"(if the build script generates it, set `inputs_generated: true`)"
                )

    # 5. One docs page per tool, both ways.
    tools = {s.parent.name for s in scripts}
    for tool in sorted(tools):
        if not (ROOT / "docs" / "benchmarks" / f"{tool}.md").is_file():
            problems.append(f"benchmarks/{tool}/ has no docs/benchmarks/{tool}.md page")
    for page in sorted((ROOT / "docs" / "benchmarks").glob("*.md")):
        if page.stem not in tools:
            problems.append(
                f"{page.relative_to(ROOT)} documents a tool with no "
                f"benchmarks/{page.stem}/*.build.sh"
            )

    # 6. The README benchmark table (one row per active tool's `default` rung)
    #    must name real programs, both ways.
    readme = (ROOT / "README.md").read_text()
    rows = re.findall(
        r"^\| \[([^\]]+)\]\(docs/benchmarks/[^)]+\) \| `([a-z0-9_]+)` \|",
        readme, re.M)
    if not rows:
        problems.append("README.md: no benchmark table rows matched — has the "
                        "table's shape changed? (expected "
                        "`| [tool](docs/benchmarks/tool.md) | `program` | …`)")
    else:
        listed_tools = set()
        for tool, prog in rows:
            listed_tools.add(tool)
            if prog not in programs:
                problems.append(
                    f"README.md: the {tool} row names `{prog}`, which is not a "
                    f"program in benchmarks/manifest.yml")
            elif programs[prog]["tool"] != tool:
                problems.append(
                    f"README.md: the {tool} row names `{prog}`, but the manifest "
                    f"lists that program under tool `{programs[prog]['tool']}`")
        # Every tool with a `default` rung is part of a bare sweep, so it belongs
        # in the table.
        for tool in sorted({p["tool"] for n, p in programs.items()
                            if n.endswith("_default")}):
            if tool not in listed_tools:
                problems.append(
                    f"README.md: tool `{tool}` has a `default` rung but no row in "
                    f"the benchmark table")

    problems += check_pins()

    # Always print the counts so the log shows what was compared.
    with_programs = len({p["tool"] for p in programs.values()})
    print(f"benchmark directories with a build script : {len(tools)}")
    print(f"  of those, in the manifest: {with_programs} with programs "
          f"+ {len(disabled)} disabled = {with_programs + len(disabled)}")
    print(f"programs in the manifest  : {len(programs)}")
    print(f"docs pages                : {len(list((ROOT / 'docs' / 'benchmarks').glob('*.md')))}")

    if problems:
        print(f"\n{len(problems)} problem(s) — benchmarks/manifest.yml does not match "
              f"the tree:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print("manifest OK")
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "list":
        cmd_list()
    elif mode == "list-run":
        cmd_list(ci_run_only=True)
    elif mode == "check":
        sys.exit(cmd_check())
    else:
        sys.exit(f"usage: {os.path.basename(sys.argv[0])} list|list-run|check")
