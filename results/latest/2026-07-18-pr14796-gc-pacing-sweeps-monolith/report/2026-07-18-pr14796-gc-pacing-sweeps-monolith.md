# PR 14796 (GC pacing) — (s, o) and off-heap (M, o) sweeps on monolith

**Date:** 2026-07-18 (s-o run started Sat 02:55; off-heap run started Sat 17:46, finished 21:24)
**Host:** monolith (AMD Ryzen 9 9950X, 16C/32T, **governor=performance**, 64 GiB, kernel 6.17)
**Compilers:** `ocaml-gc-pacing-72c712d4` (`udesou/ocaml` @ `72c712d414aa46e2e524bb2f7d1cd43abc76cb37`) vs `ocaml-trunk-e53a0322` (`e53a032298229338268c3dc3640214e1fa710c95`, the PR's merge base)
**Harness:** running-ng v0.3.8, N=5 invocations, modifiers `|re_par|md_par|pin_lavyek`
**Upstream:** [ocaml/ocaml#14796](https://github.com/ocaml/ocaml/pull/14796)

| sweep | grid | benches | runtime cells | invocations |
|---|---|---|---|---|
| **(s, o)** | s ∈ {131072, 262144, 524288, 1048576, 2097152} × o ∈ {40, 80, 120, 150, 200} (5×5) | 30 | 30 × 2 × 25 = 1500 | 7375 |
| **off-heap (M, o)** | M ∈ {11, 22, 44, 100, 250} × o ∈ {40, 80, 120, 150, 200} (5×5) | 8 | 8 × 2 × 25 = 400 | 1875 |

**Configs:** [`../logs/s-o/runbms.yml`](../logs/s-o/runbms.yml), [`../logs/offheap-M-o/runbms.yml`](../logs/offheap-M-o/runbms.yml)
**Logs:** [`../logs/s-o/`](../logs/s-o/), [`../logs/offheap-M-o/`](../logs/offheap-M-o/) (in-repo mirror — sidecars + YAML configs). Originals: `~/running-ng-pr14796/gc-sweep-logs-pr14796-s-o-native/monolith-2026-07-18-Sat-025524/` and `.../gc-sweep-logs-pr14796-offheap-M-o-native/monolith-2026-07-18-Sat-174632/`
**Notebooks:** [`../notebooks/C_gc_parameter_sweep-s-o-executed.ipynb`](../notebooks/C_gc_parameter_sweep-s-o-executed.ipynb), [`../notebooks/C_gc_parameter_sweep-offheap-M-o-executed.ipynb`](../notebooks/C_gc_parameter_sweep-offheap-M-o-executed.ipynb)
**Dashboards:**
- `ghcr.io/udesou/ocaml-bench-dashboard:pr14796-s-o-native` — committed mirror at [`../dashboard/s-o/`](../dashboard/s-o/)
- `ghcr.io/udesou/ocaml-bench-dashboard:pr14796-M-o-offheap` — committed mirror at [`../dashboard/offheap-M-o/`](../dashboard/offheap-M-o/)  
  (note: the tag is `pr14796-M-o-offheap`; there is **no** `-native` suffix on this one)

```
docker run --rm -p 8080:80 ghcr.io/udesou/ocaml-bench-dashboard:pr14796-s-o-native
```

The mirrors are ES-module apps, so `file://` will not load them — serve the directory:
`cd ../dashboard/s-o && python3 -m http.server 8080`.

**All 1900 cells captured with 5/5 invocations.** Allocation counters test clean here (`minor_words / minor_collections` = 0.94–0.99 × s), so unlike the 5.5.0 result set the `*_words` columns are trustworthy.

## TL;DR

- **gc-pacing wins wall time in all 25 (s, o) cells — no exceptions.** Geomean wall Δ ranges from **-2.6%** (s=1048576, o=40) to **-7.9%** (s=262144, o=200). At OCaml's defaults (s=262144, o=120) it is **-7.03% wall, -7.59% instructions, +3.72% RSS**. The instruction drop tracking the wall drop means the pacer is doing genuinely less work, not just spreading it better.
- **At default (s, o) not one of the 30 benches regresses more than +2%.** Worst cells: `eio_fiber_stream` +2.0%, `devkit_htmlstream` +1.0%, `sedlex_tokenize` +0.6%, `menhir_ocamly` +0.2%. Biggest wins: `liq_video_frames_pool` **-52.5%**, `owl_gc` **-45.1% wall with -71.5% RSS**, `liq_parse_typecheck` -26.4%, `zarith_pi` -16.5% (-20.9% RSS).
- **The wall win is paid for in RSS, and the price rises with `o`.** Geomean RSS Δ goes from **-1.2%** at o=40 to **+11.0%** at (s=2097152, o=200). The RSS-neutral band is the o=40 column (-1.2% to +1.9%), where the wall win is smallest (-2.6% to -4.6%). Pick the operating point deliberately: o=40 buys ~3% wall for free, o=200 buys ~7-8% wall for ~6-11% RSS.
- **The off-heap (M, o) sweep is where the PR's behaviour is dramatic — and where it can lose.** Geomean wall Δ is monotone in M: **-41.4%** at (M=11, o=200) through **-19.8%** at the M=44/o=120 default down to **+18.8%** at (M=250, o=40). RSS follows the same gradient the good way: **-27.8%** at (M=11, o=40) to +4.6% at (M=250, o=150).
- **When the off-heap budget is tight, gc-pacing is strictly better on both axes.** The whole M=11 and M=22 rows are simultaneously large wall wins and large RSS wins (M=11: -32% to -41% wall, -18% to -28% RSS). That is the regime the PR is built for, and it delivers.
- **When M is generous and `o` is low, gc-pacing loses.** (M=250, o=40) is **+18.8% wall**; (M=250, o=80) is +9.4%. The crossover sits around M=100/o=40 (+3.9%). If a deployment sets a large off-heap budget *and* a low space overhead, this PR is a regression for it — that combination deserves an explicit call in the PR discussion.
- **`liq_video_frames_pool` is the single bench driving the bad corner.** At (M=250, o=150) it is **+63.5%** wall while `owl_gc` in the same cell is -12.6%. This matches its behaviour in the (s, o) sweep, where it thrashes at non-default settings. The per-benchmark heatmaps in the notebook show every bench; the notebook's `AGGREGATE_BENCH_FILTER` knob exists to exclude it from the geomean if you want the aggregate without this outlier — **it was left unset (all benches included) for the numbers above.**
- **Intra-runtime tunability is large for both runtimes and roughly equal.** Against its own (s=524288, o=120) cell, trunk ranges -6.2% to +23.6% and gc-pacing -6.9% to +26.3%. So the PR does not reduce how much tuning matters; it shifts the whole surface down.

## Caveats

- The off-heap sweep covers only 8 benches (`alt_ergo_fill`, `cpdf_merge`, `cpdf_scale`, `cpdf_squeeze`, `liq_video_frames_pool`, `owl_gc`, `pplacer_testsuite`, `zarith_pi`), so its geomeans are far more sensitive to a single bench than the 30-bench (s, o) geomeans. The +18.8% worst cell and the -41.4% best cell are both partly `liq_video_frames_pool` and `owl_gc` swinging.
- Governor was `performance`. Absolute wall times are not comparable with the 2026-08-18 PR-14571 result set, which ran under `powersave`.
