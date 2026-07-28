#!/usr/bin/env python3
"""Regenerate the cross-version (s,o) sweep heatmap for liq_parse_typecheck
used in the OCaml workshop paper, with larger / more legible text.

Reproduces the hand-crafted paper figure (not the notebook's per-benchmark
grid): single annotated heatmap of Δ% wall time = median(d8bb46c)/median(5.4.1)
- 1 at each (s, o) cell, RdYlGn_r diverging colour scale saturating at ±40%,
with the runtime default cell (s=262144, o=120) boxed in black and the
best-found cell (s=262144, o=40) boxed in gold. Data path and median logic are
identical to notebook C (load_macro_dataframe + per-cell median). Only the
typography and export dpi change.

Run from this notebooks/ directory:
    python3 make_heatmap_fig.py
"""
import os
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from matplotlib.patches import Rectangle

from macrobench_loader import load_macro_dataframe

# --- config -------------------------------------------------------------
LOGS_DIR = Path(os.environ.get("BENCH_LOGS_DIR") or "../logs")
OUT_DIR  = Path(os.environ.get("OUT_DIR") or "~/ocaml_workshop_benchmarking").expanduser()
OUTFILE  = "fig1_liq_parse_typecheck_crossversion.png"

BENCH    = "liq_parse_typecheck"
A_VAR    = "5.4.1/baseline"     # denominator (data key)
B_VAR    = "d8bb46c/baseline"   # numerator   (data key; d8bb46c == 5.5.0-beta1)
A_LABEL  = "5.4.1"              # display label for the baseline
B_LABEL  = "5.5.0-beta1"        # display label for d8bb46c
METRIC   = "olly_wall_time_s"
MAX_PCT  = 40.0                 # colour saturation (±)

DEFAULT_CELL   = {"s": 262144, "o": 120}   # boxed black  (OCaml default)
HIGHLIGHT_CELL = {"s": 262144, "o": 40}    # boxed gold   (best found)

# Typography — the point of this script (notebook used ~9pt).
FONT = {"title": 15, "axis": 14, "tick": 13, "annot": 13, "cbar": 13, "cbartick": 12}
FIGSIZE = (8.0, 6.0)
DPI = 200


def main():
    if not LOGS_DIR.exists():
        raise SystemExit(f"LOGS_DIR does not exist: {LOGS_DIR.resolve()}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    df = load_macro_dataframe(LOGS_DIR)

    sub = df[df["benchmark"] == BENCH]
    for v in (A_VAR, B_VAR):
        if v not in set(sub["variant"].unique()):
            raise SystemExit(f"variant {v!r} not present for {BENCH}")

    a = sub[sub["variant"] == A_VAR].groupby(["o", "s"])[METRIC].median()
    b = sub[sub["variant"] == B_VAR].groupby(["o", "s"])[METRIC].median()
    delta = ((b / a) - 1.0) * 100.0
    grid = delta.unstack("s").sort_index().sort_index(axis=1)  # o asc (rows), s asc (cols)

    s_vals = [int(c) for c in grid.columns]
    o_vals = [int(r) for r in grid.index]
    z = grid.to_numpy(dtype=float)

    fig, ax = plt.subplots(figsize=FIGSIZE)
    norm = mcolors.TwoSlopeNorm(vmin=-MAX_PCT, vcenter=0.0, vmax=MAX_PCT)
    im = ax.imshow(z, origin="lower", aspect="auto", cmap="RdYlGn_r", norm=norm)

    # annotate each cell
    for i in range(z.shape[0]):
        for j in range(z.shape[1]):
            if np.isfinite(z[i, j]):
                ax.text(j, i, f"{z[i, j]:+.1f}", ha="center", va="center",
                        fontsize=FONT["annot"], color="black")

    ax.set_xticks(range(len(s_vals)))
    ax.set_xticklabels([str(s) for s in s_vals], rotation=45, ha="right",
                       fontsize=FONT["tick"])
    ax.set_yticks(range(len(o_vals)))
    ax.set_yticklabels([str(o) for o in o_vals], fontsize=FONT["tick"])
    ax.set_xlabel("s (minor heap words)", fontsize=FONT["axis"])
    ax.set_ylabel("o (space overhead)", fontsize=FONT["axis"])
    ax.set_title(f"{BENCH}: Δ% wall time  ({B_LABEL} / {A_LABEL})",
                 fontsize=FONT["title"])

    # highlight boxes
    def box(cell, color):
        if cell["s"] in s_vals and cell["o"] in o_vals:
            j = s_vals.index(cell["s"]); i = o_vals.index(cell["o"])
            ax.add_patch(Rectangle((j - 0.5, i - 0.5), 1, 1, fill=False,
                                    edgecolor=color, linewidth=3, zorder=5))
    box(DEFAULT_CELL, "black")
    box(HIGHLIGHT_CELL, "gold")

    cbar = fig.colorbar(im, ax=ax)
    cbar.set_label(f"Δ% ({B_LABEL} vs {A_LABEL})", fontsize=FONT["cbar"])
    cbar.ax.tick_params(labelsize=FONT["cbartick"])

    fig.tight_layout()
    out = OUT_DIR / OUTFILE
    fig.savefig(out, dpi=DPI, bbox_inches="tight")
    plt.close(fig)
    print(f"wrote {out}")
    print(f"  default (s={DEFAULT_CELL['s']}, o={DEFAULT_CELL['o']}) = "
          f"{grid.loc[DEFAULT_CELL['o'], DEFAULT_CELL['s']]:+.1f}%")
    print(f"  best    (s={HIGHLIGHT_CELL['s']}, o={HIGHLIGHT_CELL['o']}) = "
          f"{grid.loc[HIGHLIGHT_CELL['o'], HIGHLIGHT_CELL['s']]:+.1f}%")


if __name__ == "__main__":
    main()
