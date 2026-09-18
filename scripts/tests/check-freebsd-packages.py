#!/usr/bin/env python3
"""Check that every package the FreeBSD workflow installs actually exists.

    python3 scripts/tests/check-freebsd-packages.py

Runs on any platform: it reads FreeBSD's published package index over HTTP
rather than needing a FreeBSD host. That is the point. A wrong package name is
only discoverable on FreeBSD otherwise, and each one costs a full CI round trip
to find, one at a time.

Two real examples, both of which cost a run:

  * `opam` does not exist; FreeBSD ships it as `ocaml-opam`.
  * `py312-yaml` does not exist either. The port was renamed devel/py-yaml ->
    devel/py-pyyaml in 2024, so it is `py312-pyyaml`, and the pyXY prefix
    tracks whichever Python is default for the release.

Neither is guessable from the Linux name, and both are caught here in seconds.

Exits 0 if every name resolves, 1 if any does not, and 0 with a notice if the
index cannot be fetched, so an offline checkout or a network blip does not fail
a build over something advisory.
"""
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "ci-freebsd.yml"

#: Must match the `release:` the workflow asks vmactions for. The package set
#: differs between releases: a name valid on 14 can be absent on 15, which is
#: exactly the sort of thing this exists to catch.
ABI = "FreeBSD:15:amd64"
INDEX = "https://pkg.freebsd.org/{}/latest/packagesite.pkg".format(ABI)


def packages_from_workflow(text):
    """The names passed to `pkg install` in the workflow.

    Deliberately reads the workflow rather than taking a hardcoded list: a list
    here would be a second copy to keep in step, and the copy that drifts is
    always the one nobody runs.
    """
    lines = text.splitlines()
    names = []
    for i, line in enumerate(lines):
        # Only the main dependency list: the one written as a multi-line
        # `pkg install -y \` block. The workflow also installs PyYAML with a
        # dynamic name and an `||` fallback, which is not checkable from here
        # and does not need to be: that step verifies itself by importing the
        # module. Scraping it yields shell tokens, not package names.
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
    # The index is a zstd-compressed tar holding packagesite.yaml, which is
    # JSON-lines despite the name. Shell out rather than depend on a python
    # zstd binding that is not in the stdlib.
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
