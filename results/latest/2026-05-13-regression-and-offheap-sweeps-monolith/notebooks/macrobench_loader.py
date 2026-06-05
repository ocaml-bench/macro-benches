"""Load running-ng benchmark logs into a tidy pandas DataFrame.

Filename scheme::

    <benchmark>.<iter>.<sub_iter>.ocaml-<ocaml>
        .perf_grp<N>.re-<R>.md-<M>
        [.<gc_key>-<gc_val>]*   # zero or more GC sweep params, any order
        [.macro-<repo>]         # optional: macro-bench repository label
        .log

GC sweep tokens (``s``, ``o``, ``M``, ``m``, ...) appear in whatever order
``runbms`` emits them. Known keys land in dedicated columns; unknown keys
are preserved in ``gc_params_extra`` as a dict so future axes don't need
a loader change.

The ``<ocaml>`` segment embeds dots (e.g. ``5.4.1-flambda``) and an
optional trailing flag combo drawn from ``{fp, flambda, fp-flambda}``;
absent → ``flags = "baseline"``. Anything else in ``<ocaml>`` (including
plain git SHAs, branch names, release tags) is preserved verbatim as
``version``.

Each ``*.log`` typically has two NDJSON sidecars, ``olly_*.json`` and
``perf_*.json``, with one line per invocation. The loader emits **one
DataFrame row per invocation**, indexed by ``invocation_idx`` within
the (benchmark, version, flags, iter, sub_iter) group.
"""
from __future__ import annotations

import re
import warnings
from pathlib import Path
from typing import Iterable, List, NamedTuple, Tuple

import numpy as np
import pandas as pd
import yaml

from json_sidecars import read_json_sidecars_all


FILENAME_RE = re.compile(
    r"^(?P<benchmark>[a-z0-9_]+)"
    r"\.(?P<iter>\d+)"
    r"\.(?P<sub_iter>\d+)"
    r"\.ocaml-(?P<ocaml>[\w.-]+?)"
    r"\.perf_grp(?P<perf_grp>\d+)"
    r"\.re-(?P<re>\d+)"
    r"\.md-(?P<md>\d+)"
    # Modifier tokens after re/md: gc params with values (e.g. re_par-22),
    # plus value-less wrapper modifiers (e.g. pin_lavyek). Allow underscores
    # in the key and the trailing -<digits> is optional.
    r"(?P<gc_params>(?:\.[A-Za-z][A-Za-z0-9_]*(?:-\d+)?)*)"
    r"(?:\.macro-(?P<macro_repo>[a-z0-9-]+))?"
    r"\.log$"
)

# Same shape as the gc_params slot in FILENAME_RE: optional -<digits>.
# Value-less modifiers (e.g. pin_lavyek) get val=None and are ignored
# by _parse_gc_params, which only emits integer-valued params.
GC_PARAM_RE = re.compile(r"\.(?P<key>[A-Za-z][A-Za-z0-9_]*)(?:-(?P<val>\d+))?")

KNOWN_FLAG_SUFFIXES = ("fp-flambda", "flambda", "fp")

# GC sweep keys with a dedicated column. Extend this tuple when a new
# axis becomes part of routine sweeps; unknown keys still load into
# ``gc_params_extra`` and won't break older notebooks.
KNOWN_GC_PARAMS: tuple[str, ...] = ("s", "o", "M", "m")


def _split_ocaml(ocaml: str) -> tuple[str, str]:
    for suffix in KNOWN_FLAG_SUFFIXES:
        tail = "-" + suffix
        if ocaml.endswith(tail):
            return ocaml[: -len(tail)], suffix
    return ocaml, "baseline"


def _parse_gc_params(gc_params: str) -> tuple[dict[str, int], dict[str, int]]:
    """Split the GC-param token soup into (known, extra) integer maps.

    Value-less modifier tokens (e.g. pin_lavyek) are ignored — they're
    wrappers, not numeric params worth a column.
    """
    known: dict[str, int] = {}
    extra: dict[str, int] = {}
    for m in GC_PARAM_RE.finditer(gc_params):
        key = m.group("key")
        raw_val = m.group("val")
        if raw_val is None:
            continue
        val = int(raw_val)
        if key in KNOWN_GC_PARAMS:
            known[key] = val
        else:
            extra[key] = val
    return known, extra


def _parse_filename(name: str) -> dict | None:
    m = FILENAME_RE.match(name)
    if not m:
        return None
    fields = m.groupdict()
    version, flags = _split_ocaml(fields["ocaml"])
    known, extra = _parse_gc_params(fields["gc_params"] or "")
    row: dict = {
        "benchmark": fields["benchmark"],
        "iter": int(fields["iter"]),
        "sub_iter": int(fields["sub_iter"]),
        "version": version,
        "flags": flags,
        "variant": f"{version}/{flags}",
        "perf_grp": int(fields["perf_grp"]),
        "re": int(fields["re"]),
        "md": int(fields["md"]),
        "macro_repo": fields["macro_repo"] or None,
        "gc_params_extra": extra or None,
    }
    for key in KNOWN_GC_PARAMS:
        row[key] = known[key] if key in known else np.nan
    return row


def _flatten_olly(olly: dict | None) -> dict:
    if not olly:
        return {}
    row: dict = {
        "olly_wall_time_s": olly.get("wall_time", np.nan),
        "olly_cpu_time_s": olly.get("cpu_time", np.nan),
        "olly_gc_time_s": olly.get("gc_time", np.nan),
        "olly_gc_overhead_pct": olly.get("gc_overhead", np.nan),
        "max_rss_kb": olly.get("max_rss_kb", np.nan),
        "olly_mean_latency_ms": olly.get("mean_latency", np.nan),
        "olly_stddev_latency_ms": olly.get("stddev_latency", np.nan),
        "olly_min_latency_ms": olly.get("min_latency", np.nan),
        "olly_max_latency_ms": olly.get("max_latency", np.nan),
    }
    rss_kb = row["max_rss_kb"]
    if isinstance(rss_kb, (int, float)) and not (isinstance(rss_kb, float) and np.isnan(rss_kb)):
        row["max_rss_mb"] = rss_kb / 1024.0
    else:
        row["max_rss_mb"] = np.nan

    for pct_key, col in (
        ("50.0000", "olly_p50_latency_ms"),
        ("95.0000", "olly_p95_latency_ms"),
        ("99.0000", "olly_p99_latency_ms"),
        ("99.9000", "olly_p999_latency_ms"),
    ):
        row[col] = olly.get("distr_latency", {}).get(pct_key, np.nan)

    alloc = olly.get("allocations", {}) or {}
    row["total_heap_words"] = alloc.get("total_heap", np.nan)
    row["minor_words"] = alloc.get("minor_heap", np.nan)
    row["major_words"] = alloc.get("major_heap", np.nan)
    row["promoted_words"] = alloc.get("promoted_words", np.nan)
    row["promoted_pct"] = alloc.get("promoted_pct", np.nan)

    collections = olly.get("collections", {}) or {}
    row["minor_collections"] = collections.get("minor", np.nan)
    row["major_collections"] = collections.get("major", np.nan)
    row["forced_major_collections"] = collections.get("forced_major", np.nan)
    row["compactions"] = collections.get("compactions", np.nan)

    if row["minor_collections"]:
        row["major_per_minor"] = row["major_collections"] / row["minor_collections"]
    else:
        row["major_per_minor"] = np.nan

    return row


def _flatten_perf(perf_list: Iterable[dict] | None) -> dict:
    row: dict = {}
    if not perf_list:
        return row
    for entry in perf_list:
        event = entry.get("event")
        if not event:
            continue
        try:
            row[f"perf_{event}"] = float(entry["counter-value"])
        except (KeyError, ValueError, TypeError):
            row[f"perf_{event}"] = np.nan
        metric_val = entry.get("metric-value")
        metric_unit = entry.get("metric-unit")
        if metric_val is not None and metric_unit:
            safe_unit = re.sub(r"[^a-zA-Z0-9_]+", "_", metric_unit).strip("_").lower()
            if safe_unit:
                try:
                    row[f"perf_{event}_{safe_unit}"] = float(metric_val)
                except (ValueError, TypeError):
                    pass
    return row


def _load_rows(log_path: Path) -> list[dict]:
    fields = _parse_filename(log_path.name)
    if fields is None:
        return []
    records = read_json_sidecars_all(log_path)
    if not records:
        return [{"log_file": log_path.name, "invocation_idx": 0, **fields}]
    out: list[dict] = []
    for idx, rec in enumerate(records):
        row: dict = {"log_file": log_path.name, "invocation_idx": idx, **fields}
        row.update(_flatten_olly(rec.get("olly")))
        row.update(_flatten_perf(rec.get("perf")))
        out.append(row)
    return out


def load_macro_dataframe(logs_dir: str | Path) -> pd.DataFrame:
    """Load every ``*.log`` in ``logs_dir`` into a tidy DataFrame.

    One row per invocation. Rows with unparseable filenames are skipped
    with a warning; missing sidecars leave metric columns as NaN.
    """
    logs_dir = Path(logs_dir)
    log_files = sorted(logs_dir.glob("*.log"))
    if not log_files:
        # Sidecar-only dir: the raw *.log text is never read for metrics
        # (it only serves as a naming key for the olly_*/perf_* NDJSON
        # sidecars), so committed sidecar-only result sets are supported
        # by synthesising the log keys from the sidecars themselves.
        bases: set[str] = set()
        for p in logs_dir.glob("*.json"):
            name = p.name[: -len(".json")]
            for prefix in ("olly_", "perf_"):
                if name.startswith(prefix):
                    name = name[len(prefix):]
                    break
            bases.add(name)
        for p in logs_dir.glob("*.json.gz"):
            name = p.name[: -len(".json.gz")]
            for prefix in ("olly_", "perf_"):
                if name.startswith(prefix):
                    name = name[len(prefix):]
                    break
            bases.add(name)
        log_files = sorted(logs_dir / f"{b}.log" for b in bases)
    if not log_files:
        raise FileNotFoundError(f"No *.log files or *.json sidecars in {logs_dir}")

    rows: list[dict] = []
    skipped: list[str] = []
    for p in log_files:
        new_rows = _load_rows(p)
        if not new_rows:
            skipped.append(p.name)
        rows.extend(new_rows)

    if skipped:
        sample = ", ".join(skipped[:3])
        warnings.warn(
            f"Skipped {len(skipped)} unparseable filename(s). First few: {sample}",
            stacklevel=2,
        )

    df = pd.DataFrame(rows)
    sort_cols = ["benchmark", "version", "flags", "iter", "sub_iter", "invocation_idx"]
    df = df.sort_values(sort_cols).reset_index(drop=True)
    return df


def _resolve_baseline(df: pd.DataFrame, baseline: dict | None) -> dict:
    """Return a baseline dict that is guaranteed to match at least one row.

    If the explicit ``baseline`` is absent from ``df``, warn and pick the
    alphabetically-first ``variant`` available.
    """
    if baseline is not None:
        mask = pd.Series(True, index=df.index)
        for k, v in baseline.items():
            mask &= df[k] == v
        if mask.any():
            return baseline
        warnings.warn(
            f"Baseline {baseline} not in dataset. Available variants: "
            f"{sorted(df['variant'].unique().tolist())}. Falling back to first.",
            stacklevel=2,
        )
    first = sorted(df["variant"].unique())[0]
    version, _, flags = first.partition("/")
    return {"version": version, "flags": flags}


def baseline_normalize(
    df: pd.DataFrame,
    metric: str,
    baseline: dict | None = None,
    group_cols: Iterable[str] = ("benchmark",),
    center: str = "median",
) -> pd.DataFrame:
    """Return a copy of ``df`` with a ``{metric}_vs_baseline`` column.

    The baseline's central value (median by default; ``mean`` allowed) is
    computed per group and used as the denominator. Median is the default
    because sample sizes at this stage are too small for the central
    limit theorem to apply cleanly.

    If ``baseline`` does not match any row, a warning is issued and the
    alphabetically-first variant is used as a fallback.
    """
    if center not in ("median", "mean"):
        raise ValueError("center must be 'median' or 'mean'")
    effective = _resolve_baseline(df, baseline if baseline is not None
                                  else {"version": "5.4.1", "flags": "baseline"})

    mask = pd.Series(True, index=df.index)
    for k, v in effective.items():
        mask &= df[k] == v

    agg = "median" if center == "median" else "mean"
    base = (
        df.loc[mask]
        .groupby(list(group_cols))[metric]
        .agg(agg)
        .rename("_baseline")
    )
    out = df.merge(base, left_on=list(group_cols), right_index=True, how="left")
    out[f"{metric}_vs_baseline"] = out[metric] / out["_baseline"]
    out = out.drop(columns="_baseline")
    return out


def aggregate_invocations(
    df: pd.DataFrame,
    metrics: Iterable[str],
    group_cols: Iterable[str] = ("benchmark", "variant"),
    center: str = "median",
) -> pd.DataFrame:
    """Collapse invocations into one row per group with IQR.

    For each metric, produces ``{metric}_{center}``, ``{metric}_iqr_lo``
    (25th percentile), ``{metric}_iqr_hi`` (75th percentile), and
    ``{metric}_n``. A single ``single_invocation`` boolean column marks
    groups where every metric had ``n == 1``.
    """
    if center not in ("median", "mean"):
        raise ValueError("center must be 'median' or 'mean'")
    center_fn = "median" if center == "median" else "mean"
    metrics = list(metrics)
    group_cols = list(group_cols)

    def _agg(g: pd.DataFrame) -> pd.Series:
        out: dict = {}
        max_n = 0
        for m in metrics:
            vals = g[m].dropna()
            n = len(vals)
            max_n = max(max_n, n)
            out[f"{m}_{center}"] = vals.agg(center_fn) if n else np.nan
            out[f"{m}_iqr_lo"] = vals.quantile(0.25) if n else np.nan
            out[f"{m}_iqr_hi"] = vals.quantile(0.75) if n else np.nan
            out[f"{m}_n"] = n
        out["single_invocation"] = max_n <= 1
        return pd.Series(out)

    return df.groupby(group_cols, as_index=False).apply(_agg).reset_index(drop=True)


def export_for_ministat(
    df: pd.DataFrame,
    metric: str,
    benchmark: str,
    variant_a: str,
    variant_b: str,
    outdir: str | Path,
) -> tuple[Path, Path]:
    """Write per-invocation values for two variants to newline-separated files.

    Returns the two file paths. Files are named
    ``{metric}__{benchmark}__{variant}.txt`` with ``/`` in variant
    replaced by ``_``.

    Raises ``ValueError`` if either variant has fewer than 2
    measurements; ministat needs at least 2 samples per side.
    """
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    def _vals(v: str) -> np.ndarray:
        mask = (df["benchmark"] == benchmark) & (df["variant"] == v)
        return df.loc[mask, metric].dropna().to_numpy()

    va = _vals(variant_a)
    vb = _vals(variant_b)
    if len(va) < 2 or len(vb) < 2:
        raise ValueError(
            f"ministat needs ≥2 measurements per side; got {len(va)} for "
            f"{variant_a}, {len(vb)} for {variant_b}. Re-run the benchmarks "
            f"with more invocations."
        )

    def _safe(v: str) -> str:
        return v.replace("/", "_")

    pa = outdir / f"{metric}__{benchmark}__{_safe(variant_a)}.txt"
    pb = outdir / f"{metric}__{benchmark}__{_safe(variant_b)}.txt"
    pa.write_text("\n".join(f"{x}" for x in va) + "\n")
    pb.write_text("\n".join(f"{x}" for x in vb) + "\n")
    return pa, pb


def instruction_count_deltas(
    df: pd.DataFrame,
    baseline: dict | None = None,
    warn_threshold_pct: float = 1.0,
    regress_threshold_pct: float = 3.0,
) -> pd.DataFrame:
    """Per-(benchmark, variant) Δ% in instruction counts vs. baseline.

    Uses median across invocations. Returns columns ``benchmark``,
    ``variant``, ``baseline_instructions``, ``variant_instructions``,
    ``delta_pct``, ``verdict`` ∈ {improvement, neutral, warn, regression}.
    """
    if "perf_instructions" not in df.columns:
        raise KeyError("perf_instructions column missing — check perf group")

    eff = _resolve_baseline(df, baseline if baseline is not None
                            else {"version": "5.4.1", "flags": "baseline"})
    base_variant = f"{eff['version']}/{eff['flags']}"

    med = (df.groupby(["benchmark", "variant"])["perf_instructions"]
             .median().unstack("variant"))
    if base_variant not in med.columns:
        raise KeyError(f"baseline variant {base_variant} missing from dataset")
    base_col = med[base_variant]
    long = med.drop(columns=[base_variant]).stack().rename("variant_instructions").reset_index()
    long["baseline_instructions"] = long["benchmark"].map(base_col)
    long["delta_pct"] = (long["variant_instructions"] / long["baseline_instructions"] - 1.0) * 100.0

    def _verdict(d: float) -> str:
        if np.isnan(d):
            return "unknown"
        if d <= -regress_threshold_pct:
            return "improvement"
        if d >= regress_threshold_pct:
            return "regression"
        if abs(d) >= warn_threshold_pct:
            return "warn"
        return "neutral"

    long["verdict"] = long["delta_pct"].apply(_verdict)
    long = long[["benchmark", "variant", "baseline_instructions",
                 "variant_instructions", "delta_pct", "verdict"]]
    return long.sort_values("delta_pct", ascending=False).reset_index(drop=True)


# ---------------------------------------------------------------------------
# Paired comparisons (Issue 1).
#
# A `comparisons:` block in the runbms YAML declares which runtime pairs the
# notebook should render. Each block has shape:
#
#     - a:     <runtime>    or  [<runtime>, <runtime>, ...]
#       b:     <runtime>    or  [<runtime>, <runtime>, ...]
#       mode:  "pairwise" (default) | "cartesian"
#       label: "free-text label"   (optional)
#
# Modes:
#   pairwise  — zip a and b. A scalar on either side is broadcast to match the
#               opposite side's length (numpy-style). Lengths must match after
#               broadcasting; otherwise an error.
#   cartesian — every (x in a) × (y in b) cross.
#
# When `comparisons:` is absent or empty, the default is `BASELINE` vs every
# other variant in the dataset.
# ---------------------------------------------------------------------------


class Comparison(NamedTuple):
    """A resolved comparison block: a label and a list of variant pairs.

    Each pair is ``(a_variant, b_variant)`` where the variant strings are
    ``"<version>/<flags>"`` matching the ``variant`` column in the loaded
    DataFrame.
    """
    label: str
    pairs: List[Tuple[str, str]]


def _runtime_name_to_variant(name: str) -> str:
    """Map a runtime YAML key to the corresponding ``variant`` column value.

    Assumes the running-ng convention ``ocaml-<version>[-<flags>]``. Strips
    the ``ocaml-`` prefix and applies :func:`_split_ocaml`.
    """
    if name.startswith("ocaml-"):
        rest = name[len("ocaml-"):]
    else:
        rest = name
    version, flags = _split_ocaml(rest)
    return f"{version}/{flags}"


def _expand_pair_lists(a, b, mode: str) -> List[Tuple[str, str]]:
    """Expand the two sides of a comparison into a list of name pairs."""
    a_list = [a] if isinstance(a, str) else list(a)
    b_list = [b] if isinstance(b, str) else list(b)

    if mode == "pairwise":
        if len(a_list) == 1 and len(b_list) > 1:
            a_list = a_list * len(b_list)
        elif len(b_list) == 1 and len(a_list) > 1:
            b_list = b_list * len(a_list)
        if len(a_list) != len(b_list):
            raise ValueError(
                f"pairwise comparison requires equal-length sides; got "
                f"len(a)={len(a_list)}, len(b)={len(b_list)}. Set "
                f"`mode: cartesian` if you wanted the cross product."
            )
        return list(zip(a_list, b_list))
    if mode == "cartesian":
        return [(x, y) for x in a_list for y in b_list]
    raise ValueError(f"unknown comparison mode {mode!r}; expected 'pairwise' or 'cartesian'")


def _default_comparison(all_variants: Iterable[str], baseline: dict | None) -> Comparison:
    """Construct the fallback 'baseline vs every other variant' comparison."""
    variants = sorted(all_variants)
    if baseline is None:
        baseline = {"version": "5.4.1", "flags": "baseline"}
    base_variant = f"{baseline['version']}/{baseline['flags']}"
    if base_variant not in variants:
        if not variants:
            return Comparison(label="(no variants)", pairs=[])
        warnings.warn(
            f"Default-comparison baseline {base_variant!r} not in dataset; "
            f"falling back to {variants[0]!r}.",
            stacklevel=3,
        )
        base_variant = variants[0]
    others = [v for v in variants if v != base_variant]
    return Comparison(
        label=f"baseline ({base_variant}) vs all",
        pairs=[(base_variant, v) for v in others],
    )


def load_comparisons(
    logs_dir: str | Path,
    all_variants: Iterable[str],
    baseline: dict | None = None,
    override: list | None = None,
) -> List[Comparison]:
    """Resolve comparison blocks from ``<logs_dir>/runbms.yml``.

    Returns the user-declared blocks expanded to per-pair variant tuples.
    When the YAML has no ``comparisons:`` section (or it's empty), returns a
    single default block: ``baseline`` vs every other variant in the dataset.

    Pairs whose variants are not present in the dataset are dropped with a
    warning (so partial datasets still produce useful output).

    ``override``: when not ``None``, use this list of comparison blocks
    instead of reading them from ``runbms.yml``. Useful for ad-hoc
    exploration without touching the YAML or re-running benchmarks. The
    expected shape matches the YAML schema (a list of dicts with ``a``,
    ``b``, optional ``mode`` and ``label``).
    """
    logs_dir = Path(logs_dir)
    available = set(all_variants)

    blocks: list = []
    if override is not None:
        blocks = list(override)
    else:
        runbms = logs_dir / "runbms.yml"
        if runbms.exists():
            try:
                with runbms.open() as f:
                    config = yaml.safe_load(f) or {}
                blocks = config.get("comparisons") or []
            except yaml.YAMLError as e:
                warnings.warn(f"Failed to parse {runbms}: {e}", stacklevel=2)
                blocks = []

    if not blocks:
        return [_default_comparison(available, baseline)]

    out: List[Comparison] = []
    for i, block in enumerate(blocks):
        if not isinstance(block, dict):
            raise ValueError(
                f"comparisons[{i}] must be a mapping with 'a' and 'b' "
                f"(got {type(block).__name__}: {block!r})"
            )
        if "a" not in block or "b" not in block:
            raise ValueError(f"comparisons[{i}] missing 'a' or 'b': {block}")

        mode = block.get("mode", "pairwise")
        label = block.get("label") or f"comparison {i + 1}"
        name_pairs = _expand_pair_lists(block["a"], block["b"], mode)

        variant_pairs: List[Tuple[str, str]] = []
        for an, bn in name_pairs:
            av = _runtime_name_to_variant(an)
            bv = _runtime_name_to_variant(bn)
            missing = [name for name, v in ((an, av), (bn, bv)) if v not in available]
            if missing:
                warnings.warn(
                    f"comparison {label!r}: skipping pair ({an}, {bn}) — "
                    f"variant(s) missing from dataset: {missing}",
                    stacklevel=2,
                )
                continue
            variant_pairs.append((av, bv))

        if variant_pairs:
            out.append(Comparison(label=label, pairs=variant_pairs))

    if not out:
        warnings.warn(
            "All declared comparisons resolved to empty; falling back to default.",
            stacklevel=2,
        )
        return [_default_comparison(available, baseline)]
    return out


class ComparisonCoverage(NamedTuple):
    """Diagnostic result for the schema-sanity panel in Notebook A §2.

    All fields are sorted lists of strings.
    """
    declared_runtimes_no_data: List[str]
    data_variants_uncovered: List[str]
    declared_runtimes_total: int
    data_variants_total: int
    comparison_variants_total: int


def audit_comparison_coverage(
    logs_dir: str | Path,
    df: pd.DataFrame,
    comparisons: List[Comparison],
) -> ComparisonCoverage:
    """Cross-check ``runbms.yml`` declarations against loaded data and rendered comparisons.

    Returns a :class:`ComparisonCoverage` describing:

    * ``declared_runtimes_no_data`` — runtime keys in ``runbms.yml``'s
      ``runtimes:`` block whose variant is not present in ``df``. Usually
      means the runtime was declared but never referenced by ``configs:``,
      or the run failed for it.
    * ``data_variants_uncovered`` — variants in ``df`` that no comparison
      block currently renders. Add a comparison block (or
      ``COMPARISONS_OVERRIDE``) that mentions them, or accept the omission.
    """
    logs_dir = Path(logs_dir)
    runbms = logs_dir / "runbms.yml"

    declared_variants: set = set()
    if runbms.exists():
        try:
            with runbms.open() as f:
                config = yaml.safe_load(f) or {}
            for name in (config.get("runtimes") or {}).keys():
                declared_variants.add(_runtime_name_to_variant(name))
        except yaml.YAMLError:
            pass

    data_variants = set(df["variant"].unique()) if "variant" in df.columns else set()
    comparison_variants: set = set()
    for c in comparisons:
        for av, bv in c.pairs:
            comparison_variants.add(av)
            comparison_variants.add(bv)

    return ComparisonCoverage(
        declared_runtimes_no_data=sorted(declared_variants - data_variants),
        data_variants_uncovered=sorted(data_variants - comparison_variants),
        declared_runtimes_total=len(declared_variants),
        data_variants_total=len(data_variants),
        comparison_variants_total=len(comparison_variants),
    )
