#!/usr/bin/env python3
"""Check that every package the FreeBSD workflow installs exists in FreeBSD's
published package index, from any platform.

    python3 scripts/tests/check-freebsd-packages.py

Names are not guessable from Linux (`opam` is `ocaml-opam`, `py312-yaml` is
`py312-pyyaml`). Exits 1 on a bad name; exits 0 with a notice if the index
cannot be fetched (advisory, not a gate).
"""
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "ci-freebsd.yml"

#: Must match the workflow's `release:`; the package set differs between releases.
ABI = "FreeBSD:15:amd64"
INDEX = "https://pkg.freebsd.org/{}/latest/packagesite.pkg".format(ABI)


def packages_from_workflow(text):
    """The names passed to `pkg install` in the workflow (read, not hardcoded, so
    there is no second copy to drift)."""
    lines = text.splitlines()
    names = []
    for i, line in enumerate(lines):
        # Only the multi-line `pkg install -y \` block; the PyYAML install uses a
        # dynamic name with an `||` fallback and verifies itself.
        if "pkg install -y" not in line or not line.rstrip().endswith("\\"):
            continue
        j = i + 1
        while j < len(lines):
            cur = lines[j].strip()
            names.extend(cur.rstrip("\\").split())
            if not cur.endswith("\\"):
                break
            j += 1
        break
    return [n for n in names if "${" not in n]


def repo_package_names():
    with urllib.request.urlopen(INDEX, timeout=60) as fh:
        blob = fh.read()
    try:
        import zstandard  # noqa: F401
    except ImportError:
        pass
    # The index is a zstd tar holding packagesite.yaml (JSON lines despite the
    # name). Shell out: no zstd binding in the stdlib.
    import subprocess
    import tarfile
    import io

    raw = subprocess.run(["zstd", "-dc"], input=blob, capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(raw)) as tf:
        member = tf.extractfile("packagesite.yaml")
        names = set()
        for line in member:
            try:
                names.add(json.loads(line.decode("utf-8", "replace"))["name"])
            except Exception:
                continue
    return names


def main():
    if not WORKFLOW.exists():
        print("no {}; nothing to check".format(WORKFLOW))
        return 0

    wanted = packages_from_workflow(WORKFLOW.read_text())
    if not wanted:
        print("could not find a `pkg install` list in {}".format(WORKFLOW.name), file=sys.stderr)
        return 1

    try:
        have = repo_package_names()
    except (urllib.error.URLError, OSError, Exception) as exc:  # noqa: BLE001
        print("could not fetch {}: {}".format(INDEX, exc))
        print("skipping (advisory check, not a gate)")
        return 0

    missing = [p for p in wanted if p not in have]
    print("{}: {} packages in the index, {} requested by the workflow".format(
        ABI, len(have), len(wanted)))
    for p in sorted(wanted):
        print("  {:<16} {}".format(p, "ok" if p in have else "NOT IN REPO"))

    if missing:
        print("\nnot available in {}: {}".format(ABI, ", ".join(sorted(missing))), file=sys.stderr)
        print("Search the real name at https://www.freshports.org/ , or with", file=sys.stderr)
        print("  pkg search <term>   on a FreeBSD host.", file=sys.stderr)
        return 1

    print("\nall package names resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
