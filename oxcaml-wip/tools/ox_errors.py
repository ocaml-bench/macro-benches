"""Group distinct compile errors from macro-benches ci-logs/build/*.log by file.

Usage: python3 ox_errors.py [ci-logs/build]  (prints file, line, first error lines)
"""
import collections
import glob
import os
import re
import sys

logdir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/macro-benches/ci-logs/build")
errors = collections.OrderedDict()
programs = collections.defaultdict(set)
for log in sorted(glob.glob(os.path.join(logdir, "*.log"))):
    prog = os.path.basename(log)[:-4]
    text = open(log, errors="replace").read()
    for block in re.split(r"\n(?=File \")", text):
        m = re.match(r'File "([^"]+)", line (\d+)', block)
        if not m or "\nError" not in block:
            continue
        lines = block.split("\n")
        i = next(k for k, l in enumerate(lines) if l.startswith("Error"))
        body = []
        for l in lines[i:i + 16]:
            if l.startswith(("File ", "Leaving", "Entering", "[")) and body:
                break
            body.append(l.rstrip())
        key = (m.group(1), m.group(2))
        errors.setdefault(key, "\n".join(body[:14]))
        programs[key].add(prog)

for (path, line), body in errors.items():
    print(f"===== {path}:{line}  ({len(programs[(path, line)])} programs)")
    print(body)
print(f"\n{len(errors)} distinct errors")
