"""NDJSON sidecar discovery and parsing for running-ng benchmark logs.

Each ``<name>.log`` produced by running-ng may have companion NDJSON
sidecars written by the ``olly`` and ``perf`` tool wrappers. Each line
in a sidecar corresponds to one invocation of the benchmark; callers
that want per-invocation data should use :func:`read_ndjson_all`, while
callers that want only the most recent record can use
:func:`read_ndjson_last`.
"""
import gzip
import json
from pathlib import Path
from typing import List, Optional


def find_tool_sidecars(log_path: Path) -> dict:
    """Return a dict mapping tool name to its NDJSON sidecar path.

    Looks for new-format per-tool sidecars (``olly_<base>.json``,
    ``perf_<base>.json``) and also the old combined-single-sidecar
    format (``<base>.json``) for backward compat.
    """
    stem = log_path.name
    if stem.endswith(".log.gz"):
        base = stem[: -len(".log.gz")]
    elif stem.endswith(".log"):
        base = stem[: -len(".log")]
    else:
        return {}

    found = {}
    for tool in ("olly", "perf"):
        for cand in (log_path.parent / f"{tool}_{base}.json",
                     log_path.parent / f"{tool}_{base}.json.gz"):
            if cand.exists():
                found[tool] = cand
                break
    if not found:
        for cand in (log_path.parent / f"{base}.json",
                     log_path.parent / f"{base}.json.gz"):
            if cand.exists():
                found["_combined"] = cand
                break
    return found


def _read_text(path: Path) -> str:
    if path.name.endswith(".gz"):
        raw = gzip.open(path, "rb").read()
    else:
        raw = path.read_bytes()
    return raw.decode("utf-8", errors="replace")


def read_ndjson_all(path: Path) -> List[dict]:
    """Read every record from an NDJSON file (plain or gzipped).

    Returns them in file order. Blank lines are skipped; malformed lines
    cause the whole file to be treated as empty (returns ``[]``) rather
    than partially parsing.
    """
    try:
        text = _read_text(path).strip()
        if not text:
            return []
        records = []
        for line in text.splitlines():
            line = line.strip()
            if line:
                records.append(json.loads(line))
        return records
    except Exception:
        return []


def read_ndjson_last(path: Path) -> Optional[dict]:
    """Read the last record from an NDJSON file (plain or gzipped)."""
    try:
        text = _read_text(path).strip()
        if not text:
            return None
        for line in reversed(text.splitlines()):
            line = line.strip()
            if line:
                return json.loads(line)
        return None
    except Exception:
        return None


def read_json_sidecar(log_path: Path) -> Optional[dict]:
    """Collect the latest invocation's data from per-tool sidecars.

    Returns a dict shaped like the legacy combined sidecar — ``{"olly":
    ..., "perf": ...}`` — so callers are agnostic to the file layout.
    """
    sidecars = find_tool_sidecars(log_path)
    if not sidecars:
        return None
    if "_combined" in sidecars:
        return read_ndjson_last(sidecars["_combined"])
    merged: dict = {}
    for tool, path in sidecars.items():
        data = read_ndjson_last(path)
        if data is not None:
            merged[tool] = data
    return merged or None


def read_json_sidecars_all(log_path: Path) -> List[dict]:
    """Collect per-invocation data from per-tool sidecars.

    Returns a list of ``{"olly": ..., "perf": ...}`` dicts, one per
    invocation. The length is the minimum line count across the tool
    sidecars that were found — if olly has 3 lines and perf has 2, only
    2 aligned records are returned.

    The legacy combined sidecar (one file with both tools' data) is
    treated as a single-invocation record.
    """
    sidecars = find_tool_sidecars(log_path)
    if not sidecars:
        return []
    if "_combined" in sidecars:
        rec = read_ndjson_last(sidecars["_combined"])
        return [rec] if rec is not None else []

    per_tool: dict = {}
    for tool, path in sidecars.items():
        records = read_ndjson_all(path)
        if records:
            per_tool[tool] = records
    if not per_tool:
        return []

    n = min(len(v) for v in per_tool.values())
    out: List[dict] = []
    for i in range(n):
        merged = {tool: per_tool[tool][i] for tool in per_tool}
        out.append(merged)
    return out
