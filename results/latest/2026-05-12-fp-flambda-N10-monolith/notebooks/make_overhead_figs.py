#!/usr/bin/env python3
"""Regenerate the per-benchmark wall-time overhead tornado plots for the
OCaml workshop paper, with larger / more legible text.

Faithful to notebook A's `_tornado_grid`: same data path (load_macro_dataframe),
same per-benchmark Δ% = median(b)/median(a) - 1, same colours, same sort, same
title format ("5.4.1/baseline  ->  5.4.1/fp"). The only change is typography:
bigger tick/label/title fonts and a tight, higher-dpi export so the text stays
readable when the figure is shrunk to ~0.48\\textwidth in the two-column layout.

Run from this notebooks/ directory (so ../logs and macrobench_loader resolve):
    python3 make_overhead_figs.py
Override paths if needed:
    BENCH_LOGS_DIR=../logs OUT_DIR=~/ocaml_workshop_benchmarking python3 make_overhead_figs.py
"""
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # no display needed
import matplotlib.pyplot as plt

from macrobench_loader import load_macro_dataframe

# --- config -------------------------------------------------------------
LOGS_DIR = Path(os.environ.get("BENCH_LOGS_DIR") or "../logs")
OUT_DIR  = Path(os.environ.get("OUT_DIR") or "~/ocaml_workshop_benchmarking").expanduser()
METRIC   = "olly_wall_time_s"
BASELINE = "5.4.1/baseline"
TARGETS  = [
    ("5.4.1/fp",      "overhead-fp.png"),
    ("5.4.1/flambda", "overhead-flambda.png"),
]

# Typography — the whole point of this script. Bump these if still too small.
FONT = {
    "ytick":  13,   # benchmark names (was 7 in the notebook grid)
    "xtick":  13,   # axis numbers
    "xlabel": 15,
    "title":  16,
}
FIGSIZE = (6.5, 9.0)   # inches; portrait, ~34 benchmarks
DPI     = 200

# Notebook palette: green = improvement (Δ<0), orange = regression (Δ>=0).
C_IMPROVE = "#2a9d8f"
C_REGRESS = "#e76f51"


def delta_per_bench(df, av, bv, metric):
    """Δ% per benchmark for the median ratio of (b vs a) — identical to notebook A."""
    a = df[df["variant"] == av].groupby("benchmark")[metric].median()
    b = df[df["variant"] == bv].groupby("benchmark")[metric].median()
    return ((b / a) - 1.0).dropna() * 100.0


def plot_tornado(df, av, bv, metric, outpath):
    d = delta_per_bench(df, av, bv, metric).sort_values()
    if d.empty:
        print(f"  !! no data for {av} -> {bv}; skipping {outpath.name}")
        return
    colors = [C_IMPROVE if x < 0 else C_REGRESS for x in d.values]

    fig, ax = plt.subplots(figsize=FIGSIZE)
    ax.barh(d.index, d.values, color=colors)
    ax.axvline(0, color="black", linewidth=0.8)
    ax.set_title(f"{av}  →  {bv}", fontsize=FONT["title"])
    ax.set_xlabel("wall time Δ%", fontsize=FONT["xlabel"])
    ax.tick_params(axis="y", labelsize=FONT["ytick"])
    ax.tick_params(axis="x", labelsize=FONT["xtick"])
    ax.margins(y=0.01)
    fig.tight_layout()
    fig.savefig(outpath, dpi=DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"  wrote {outpath}  ({len(d)} benchmarks, "
          f"range {d.min():.1f}%..{d.max():.1f}%)")


def main():
    if not LOGS_DIR.exists():
        raise SystemExit(f"LOGS_DIR does not exist: {LOGS_DIR.resolve()}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"LOGS_DIR = {LOGS_DIR.resolve()}")
    print(f"OUT_DIR  = {OUT_DIR}")

    df = load_macro_dataframe(LOGS_DIR)
    variants = sorted(df["variant"].unique())
    print(f"variants present: {variants}")
    if BASELINE not in variants:
        raise SystemExit(f"baseline variant {BASELINE!r} not in dataset")

    for target, fname in TARGETS:
        if target not in variants:
            print(f"  !! {target!r} not in dataset; skipping {fname}")
            continue
        plot_tornado(df, BASELINE, target, METRIC, OUT_DIR / fname)


if __name__ == "__main__":
    main()
