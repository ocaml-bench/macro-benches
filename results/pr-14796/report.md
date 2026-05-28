# ocaml/ocaml#14796 (new GC pacing) vs trunk merge-base — full (s, o) sweep (monolith, **N=5, 5×5 grid**)

**Date:** 2026-05-26 (run started Tue 10:03)
**Host:** monolith (AMD Ryzen 9 9950X, 16C/32T, governor=performance, 64 GiB, kernel 6.17)
**Compilers:**
  - `ocaml-trunk-cfb30145` — merge-base of [ocaml/ocaml#14796](https://github.com/ocaml/ocaml/pull/14796) (`cfb30145`)
  - `ocaml-gc-pacing` — PR head + stdlib runtime_events sync ([`udesou/ocaml#gc-pacing-new+stdlib-events`](https://github.com/udesou/ocaml/tree/gc-pacing-new%2Bstdlib-events))
**Sweep:** s ∈ {131072, 262144, 524288, 1048576, 2097152} × o ∈ {40, 80, 120, 150, 200} (5×5)
**Config:** [`running-ng/src/running/config/experiments/pr14796_gc_pacing_vs_trunk.yml`](https://github.com/udesou/running-ng/blob/pr14796-per-runtime-olly/src/running/config/experiments/pr14796_gc_pacing_vs_trunk.yml) (running-ng branch `pr14796-per-runtime-olly`)
**Modifiers:** `|perf_grp1|re-25|md-2|re_par-22|md_par-8|pin_lavyek`
**Logs:** [`logs/`](logs) (mirror of `~/running-ng/gc-sweep-logs-pr14796-2026-05-26/monolith-2026-05-26-Tue-100301/` — `runbms.yml` + per-(bench, runtime, s, o) `olly_*.json` and `perf_*.json` JSONL sidecars)
**Notebooks (executed):** [`notebooks/A_regression_dashboard-executed.ipynb`](notebooks/A_regression_dashboard-executed.ipynb), [`notebooks/C_gc_parameter_sweep-executed.ipynb`](notebooks/C_gc_parameter_sweep-executed.ipynb).
**Companion:** [`../latest/2026-05-16-full-s-o-sweep-monolith.md`](../latest/2026-05-16-full-s-o-sweep-monolith.md) — same grid for 5.4.1 vs d8bb46c; the heatmap method/shape is the comparison baseline.

## Sanity check (read this first)

- **Grid completeness:** every (bench, runtime, s, o) cell present, **5/5 invocations** captured. gc-pacing ran 23 benches × 25 cells; trunk ran 24 (it additionally builds `pplacer_testsuite`, which still fails on gc-pacing). alt_ergo×3 and jsoo fail to build on both — same exclusion set as the N=10 run. No parse errors, no missing cells.
- **⚠️ `liq_video_frames_pool` on gc-pacing is broken at every non-default `o`.** Only the 5 `o=120` cells are valid (~2.20s, ~395 major GCs). The other 20 cells are unusable:
  - `o∈{150,200}` (all s) and `o∈{40,80}` (small s): olly emitted **negative wall_time** (~−5.58×10⁶ s) — its event stream broke.
  - `o=40` and a couple of `o=80` cells that *did* produce a number: **37–115 s** wall with **1500–3049 major collections** (vs 395 at o=120) and `gc_time` pinned at ~120 s — i.e. the process genuinely thrashed and hit the 120 s timeout cap.
  - **Trunk runs this same bench cleanly across all 25 cells** (wall 2.76–3.57 s, majors 899→1156, smoothly responsive to `o`, flat in `s`). So this is **gc-pacing-specific**, not a harness artifact — the new pacer is pathological on this allocation-churning video-frame-pool workload once `space_overhead` moves off its default.
  - **Confirmed by hand outside running-ng/olly** (2026-05-26, `/usr/bin/time -v`, same binary, arg 30000, `s=262144`, `timeout 120`): gc-pacing `o=120` → **2.20 s** (✓, matches olly), gc-pacing `o=40` → **110.7 s** (Exit 0, 99% CPU — completes, 50× slower), gc-pacing `o=80` → **killed at 120 s** (SIGTERM, exit 143 — this is the source of the negative olly wall: a real timeout kill truncates olly's event stream), trunk `o=40` → **3.49 s** (✓). RSS is identical (~107 MB) in every case — the regression is pure GC/CPU time, not memory. **The negative wall_times are therefore real timeout kills, not an olly decode bug**, and the slowdown is a genuine PR-14796 pacer regression at low `space_overhead`. **Excluded from all aggregate heatmaps below.**
- **Everything else is clean.** A handful of cells trip a >25% within-cell wall-spread flag (`devkit_stre`, `coqc_corelib_stress`@131072, `eio_fiber_stream`@(1048576,40)) — these are known-noisy benches at N=5, not corruption (devkit_stre's high variance is called out in the N=10 report too). Medians are trustworthy; treat their magnitudes as soft.

## TL;DR

- **The default cell reproduces the N=10 baseline.** owl_gc −43.2% wall / −98.6% maj / −71.5% RSS, zarith_pi −16.2% / −78.7% / −18.7%, liq_parse_typecheck −23.8% / −77.1%, devkit_stre −9.7% / −77.2%; every major-GC delta matches 2026-05-25 to the integer. The sweep run is consistent with the established baseline.
- **gc-pacing wins everywhere on the grid.** Cross-runtime geomean wall is **−2.2% to −6.2% in favour of gc-pacing at every one of the 25 cells** (22-bench set), slightly larger at small `s` / aggressive `o`. The PR's advantage is **not** a default-tuning artifact — it survives the whole (s, o) space.
- **Major-GC reduction is the headline signal and is grid-wide**, same as N=10: the typical bench runs far fewer major collections on gc-pacing at every cell.
- **Intra-runtime (s, o) response is near-identical between the two runtimes.** Both get faster toward larger `s` + higher `o` (best quadrant ≈ −9 to −12% wall at `(2097152, 200)`) and pay RSS for high `o`. The new pacer **does not change how a workload responds to tuning** — it shifts the whole surface down by the ~2–6% cross-runtime win.
- **RSS trade-off slightly steeper on gc-pacing at high `o`:** at `(2097152, 200)` gc-pacing holds +22.1% RSS vs its default, trunk +11.8% — consistent with the pacer running the major slice less often and letting the heap float higher.

## Validation — default cell (s=262144, o=120), N=5 medians

| bench | trunk wall | gcp wall | Δwall% | trunk maj | gcp maj | Δmaj% | trunk RSS | gcp RSS | ΔRSS% |
|---|---|---|---|---|---|---|---|---|---|
| coqc_corelib_stress | 17.09 | 17.14 | +0.3% | 25 | 25 | +0.0% | 1085 | 1085 | -0.0% |
| cpdf_blacktext | 2.50 | 2.48 | -0.8% | 29 | 23 | -20.7% | 252 | 273 | +8.4% |
| cpdf_merge | 2.13 | 2.10 | -1.4% | 28 | 21 | -25.0% | 369 | 428 | +16.2% |
| cpdf_scale | 12.85 | 12.79 | -0.5% | 56 | 47 | -16.1% | 480 | 557 | +16.0% |
| cpdf_squeeze | 3.43 | 3.40 | -0.9% | 34 | 27 | -20.6% | 339 | 344 | +1.6% |
| devkit_gzip | 2.54 | 2.51 | -1.2% | 1092 | 239 | -78.1% | 17 | 19 | +14.3% |
| devkit_htmlstream | 6.93 | 6.99 | +0.9% | 255 | 175 | -31.4% | 358 | 422 | +17.9% |
| devkit_network | 4.93 | 5.03 | +2.0% | 179 | 70 | -60.9% | 85 | 96 | +12.3% |
| devkit_stre | 4.45 | 4.02 | -9.7% ✓ | 2333 | 533 | -77.2% | 23 | 26 | +14.7% |
| eio_fiber_stream | 1.93 | 1.99 | +3.1% | 1171 | 260 | -77.8% | 33 | 35 | +6.1% |
| irmin_mem_rw | 4.03 | 3.96 | -1.7% | 185 | 134 | -27.6% | 36 | 41 | +13.5% |
| liq_parse_typecheck | 9.74 | 7.42 | -23.8% ✓ | 14583 | 3341 | -77.1% | 48 | 51 | +5.9% |
| liq_video_frames_pool | 2.97 | 2.20 | -25.9% ✓ | 981 | 395 | -59.7% | 110 | 119 | +8.8% |
| menhir_ocamly | 12.43 | 13.02 | +4.7% | 25 | 19 | -24.0% | 2684 | 2717 | +1.3% |
| menhir_sql_parser | 1.20 | 1.17 | -2.5% | 20 | 15 | -25.0% | 269 | 286 | +6.4% |
| menhir_sysver | 7.62 | 7.64 | +0.3% | 55 | 46 | -16.4% | 746 | 815 | +9.3% |
| ocamlc_self_compile | 3.40 | 3.35 | -1.5% | 12 | 10 | -16.7% | 974 | 1038 | +6.6% |
| ocamlformat_rocq | 1.80 | 1.79 | -0.6% | 22 | 16 | -27.3% | 297 | 336 | +12.9% |
| owl_gc | 3.31 | 1.88 | **-43.2%** ✓ | 26787 | 369 | **-98.6%** | 125 | 36 | **-71.5%** ✓ |
| sedlex_tokenize | 1.57 | 1.58 | +0.6% | 9 | 8 | -11.1% | 945 | 931 | -1.5% |
| test_decompress | 1.71 | 1.68 | -1.8% | 1600 | 576 | -64.0% | 15 | 17 | +8.4% |
| ydump_repeat | 2.52 | 2.49 | -1.2% | 1774 | 500 | -71.8% | 11 | 13 | +16.2% |
| zarith_pi | 2.59 | 2.17 | **-16.2%** ✓ | 53342 | 11382 | -78.7% | 125 | 102 | **-18.7%** ✓ |

✓ = ≥5% wall improvement / ≥10% RSS decrease on gc-pacing. `menhir_ocamly` +4.7% is again the only meaningful (sub-5%) wall regression, matching N=10's +4.4%.

## Cross-runtime geomean Δ% WALL (gc-pacing vs trunk) at every cell — 22 benches

Negative = gc-pacing faster. **gc-pacing wins in all 25 cells.**

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | -5.7 | -4.8 | -3.7 | -2.8 | -2.2 |
| **80** | -6.0 | -6.2 | -3.7 | -3.0 | -3.5 |
| **120 (def)** | -4.7 | -5.0 | -4.0 | -3.1 | -3.2 |
| **150** | -4.4 | -5.0 | -4.1 | -3.5 | -3.2 |
| **200** | -3.7 | -4.7 | -4.4 | -3.4 | -3.1 |

The win is largest in the small-`s` / aggressive-`o` corner (where trunk over-collects most and gc-pacing's smarter pacing helps most) and shrinks toward large `s` (where both runtimes already collect rarely), but never disappears.

## Intra-runtime (s, o) response — gc-pacing vs trunk, 22 benches

### gc-pacing — geomean Δ% WALL vs gc-pacing default

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | +19.5 | +10.9 | +6.2 | +2.4 | +1.2 |
| **80** | +9.0 | +2.9 | -1.4 | -4.2 | -5.8 |
| **120 (def)** | +6.6 | +0.0 | -4.0 | -6.9 | -8.7 |
| **150** | +4.7 | -1.2 | -5.0 | -8.3 | -9.6 |
| **200** | +3.2 | -2.7 | -6.4 | -9.1 | **-10.5** |

### trunk — geomean Δ% WALL vs trunk default

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | +20.3 | +10.7 | +4.7 | +0.0 | -1.8 |
| **80** | +10.1 | +4.2 | -2.8 | -6.2 | -7.4 |
| **120 (def)** | +6.3 | +0.0 | -5.0 | -8.8 | -10.4 |
| **150** | +3.9 | -1.2 | -5.9 | -9.8 | -11.3 |
| **200** | +1.8 | -3.0 | -7.0 | -10.7 | **-12.3** |

### gc-pacing — geomean Δ% RSS vs gc-pacing default

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | -3.1 | -11.3 | **-14.6** | -10.4 | -0.3 |
| **80** | +3.2 | -5.1 | -8.7 | -5.3 | +6.8 |
| **120 (def)** | +9.0 | +0.0 | -1.8 | -0.2 | +11.9 |
| **150** | +15.0 | +4.4 | +1.5 | +3.3 | +15.3 |
| **200** | +17.4 | +8.9 | +5.0 | +8.9 | +22.1 |

### trunk — geomean Δ% RSS vs trunk default

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | +1.4 | -6.9 | **-12.5** | -10.3 | -1.1 |
| **80** | +5.6 | -2.5 | -7.4 | -4.7 | +3.7 |
| **120 (def)** | +5.7 | +0.0 | -3.2 | -2.2 | +7.2 |
| **150** | +8.6 | +2.7 | -0.1 | +1.3 | +8.7 |
| **200** | +10.6 | +7.3 | +3.0 | +4.9 | +11.8 |

**Reading the four heatmaps:** the wall surfaces are nearly congruent (both runtimes get ~10–12% faster toward `(2097152, 200)`, both pay ~20% at `(131072, 40)`) — gc-pacing does not alter tuning sensitivity, it just sits ~2–6% lower everywhere (the cross-runtime table). On RSS, the best-RSS cell is `(524288, 40)` for both (gcp −14.6%, trunk −12.5%), and gc-pacing's high-`o` RSS cost is steeper (top-right corner +22% vs +12%) — the pacer trades RSS for fewer majors more aggressively as `o` grows.

## Follow-ups

1. **`liq_video_frames_pool` on gc-pacing at non-default `o` — confirmed regression, file upstream.** Verified by hand (see sanity section): at `s=262144`, gc-pacing runs 2.2 s @ o=120 → 110.7 s @ o=40 → >120 s (timeout) @ o=80, while trunk is flat (~3.5 s @ o=40). The 1500–3049 major collections (vs 395 at o=120, trunk's flat ~1000) point at the new pacer's `space_overhead` handling over-collecting catastrophically on this allocation-churning workload. This is a concrete PR-14796 regression worth a minimal repro for the PR thread (the binary + `OCAMLRUNPARAM=...,o=40` reproduces it standalone in seconds). A clean N≥3 sweep number for the report would need a raised timeout cap so the o≠120 cells don't get killed.
2. **No new default recommendation.** As in the 5-16 sweep, the best balanced intra-gcp cell is roughly `(1048576, 80)` (−4.2% wall, −5.3% RSS), but no cell passes a 10% per-bench safety filter (devkit_gzip's tiny RSS baseline swings >10%). This is a tuning-surface characterisation, not a ship-a-default proposal.
3. The three infrastructure dependencies (ppxlib #642, per-runtime olly, stdlib runtime_events sync) from the N=10 report apply unchanged — the Δmaj numbers are only trustworthy because of the stdlib sync.
