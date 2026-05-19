# Full-suite (s, o) sweep — 5.4.1 vs d8bb46c on monolith

**Date:** 2026-05-16 (run started Sat 03:26)
**Host:** monolith (AMD Ryzen 9 9950X, 16C/32T, governor=performance, 64 GiB, kernel 6.17)
**Compilers:** `ocaml-5.4.1` (release) vs `ocaml-d8bb46c39bf5fcafb513a8ba18e667d3f8c2600a` (5.5-beta) — base, no `-fp`/`-flambda`

| sweep | grid | benches | runtime cells | invocations |
|---|---|---|---|---|
| **Full (s, o)** | s ∈ {131072, 262144, 524288, 1048576, 2097152} × o ∈ {40, 80, 120, 150, 200} (5×5) | 32 — the full base list (macro-merlin disabled) | 32 × 2 × 25 = 1600 | 8000 |

**Config:**
[full_s_o_sweep_2026_05_16.yml](../../running-ng/src/running/config/experiments/full_s_o_sweep_2026_05_16.yml)
**Logs:** `~/running-ng/gc-sweep-logs-sweep-s-o-2026-05-16/monolith-2026-05-16-Sat-032651/`
**Companion reports:**
- [2026-05-13-regression-and-offheap-sweeps-monolith.md](2026-05-13-regression-and-offheap-sweeps-monolith.md) — the 13-bench (s, o) regression-subset sweep at N=3 that this run extends to the full suite at N=5.
- [2026-05-12-fp-flambda-5.4.1-vs-d8bb46c-monolith-N10.md](2026-05-12-fp-flambda-5.4.1-vs-d8bb46c-monolith-N10.md) — the headline N=10 monolith run.

**All 1600 cells captured with 5/5 invocations.** N=5 doubled the sampling vs the 5-13 N=3 sweep — within-cell wall spread median is 1.3% (vs 1.7% on the 5-13 sweep).

## TL;DR

- **The 13 regressed benches from 5-13 reproduce cleanly at N=5.** The headline cross-version effects at default `(s=262144, o=120)` are within ±2 percentage points of 5-13:
  `liq_parse_typecheck` +5.9% wall (5-13: +6.6), `jsoo` +16.1% (+15.8), `alt_ergo_fill` +8.7% (+8.4), `ocamlc_self_compile` +8.5% (+9.6), `cpdf_merge` +6.2% (+4.9), `cpdf_scale` +5.1% (+5.4), `menhir_sysver` +6.2% (+5.6), `ocamlformat_rocq` +4.6% (+4.7), `devkit_stre` -3.7% (-3.5). The conclusions in [2026-05-13-regression-and-offheap-sweeps-monolith.md](2026-05-13-regression-and-offheap-sweeps-monolith.md) carry over to N=5.
- **New (s, o) finding on `coqc_corelib_stress`** — cross-version flat (±3% across the grid), but the **intra-runtime tunability is extreme**: at `(s=2097152, o=200)` d8b is **-73.1% wall** vs d8b at default `(s=262144, o=120)` (17.22s → 4.63s). Both runtimes scale the same way with `s`; this is a workload-side story (the coq kernel is allocation-throughput-bound on a small minor heap), not a runtime story. Equivalent finding on 5.4.1 (-72.7% wall).
- **`eio_fiber_stream` is a new cross-version d8b win at low s.** At `(s=131072, o=40)`: d8b is **-16.4% wall, -21% RSS** vs 5.4. At default it's a small d8b regression (+1.9%). No equivalent shape in the 5-13 subset.
- **`alt_ergo_unsat_smt2` shows extreme cross-version RSS savings.** At `(s=1048576, o=200)` d8b uses **-45% RSS** vs 5.4 with neutral wall (-0.1%). This is a much stronger RSS Pareto than 5-13's headline benches; alt_ergo_unsat_smt2 wasn't in that subset because its default-cell wall regression is sub-threshold (-0.1%).
- **`devkit_gzip` is a quiet d8b winner at low `o`.** At `(s=262144, o=40)`: **-8.9% wall, -11% RSS** — a strict-improve cell. The default-cell effect is already mildly negative (-4.2% wall), making this another "d8b wins, just less obviously" bench in the spirit of devkit_stre. Note: devkit_gzip has a tiny RSS baseline (17 MB) — large % swings in the intra-d8b view are absolute changes of a few MB.
- **`irmin_mem_rw` opens up cleanly on intra-d8b at large `s`.** At `(s=2097152, o=120)` intra-d8b is **-14.9% wall, -10% RSS** vs d8b default. Cross-version flat-to-slight regression (+3.3% at default), but the intra-runtime view says irmin-style Lwt workloads benefit substantially from a larger minor heap on d8b.
- **The cross-version Pareto picture for the new 19 benches is favourable on the headline metrics.** Across the full 32-bench set, the geomean intra-d8b heatmap shows that **`(s=1048576, o=80)`** is the best balanced cell (wall geo-Δ% = -3.8%, RSS geo-Δ% = -5.4%) — both axes improved over default by tuning toward larger s and slightly more-aggressive major-pacer pressure. The same shape repeats for 5.4.1: best Pareto cell is `(s=1048576, o=40)` with -15.3% RSS at +4.3% wall, or `(s=1048576, o=80)` with both axes negative (-2.5% wall, -8.0% RSS).

## Cross-version geomean overall picture — both runtimes

The "overall picture" heatmaps below are the cross-bench geomean Δ% at each
`(s, o)` cell — the new view added to notebook
[C_gc_parameter_sweep.ipynb](../../running-ng/notebooks/C_gc_parameter_sweep.ipynb)
§3 (intra-runtime aggregate). Rows = `o`, columns = `s`; values are %.

### d8b — geomean Δ% wall vs d8b default `(s=262144, o=120)`

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | +16.9 | +10.0 | +5.4 | +2.6 | +1.9 |
| **80** | +7.6 | +3.2 | -1.4 | -3.8 | -4.2 |
| **120** **(def)** | +4.1 | 0.0 | -3.9 | -6.5 | -7.4 |
| **150** | +2.3 | -1.0 | -5.0 | -7.6 | -8.1 |
| **200** | +0.3 | -3.2 | -6.3 | -8.4 | **-9.1** |

### d8b — geomean Δ% RSS vs d8b default `(s=262144, o=120)`

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | -1.1 | -8.1 | **-11.8** | -10.1 | -3.2 |
| **80** | +3.4 | -2.8 | -7.3 | -5.4 | +1.7 |
| **120** **(def)** | +5.5 | 0.0 | -2.9 | -1.5 | +5.0 |
| **150** | +7.4 | +2.6 | -0.5 | +0.9 | +7.8 |
| **200** | +9.2 | +5.3 | +2.1 | +3.8 | +9.8 |

### 5.4.1 — geomean Δ% wall vs 5.4.1 default `(s=262144, o=120)`

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | +20.5 | +13.5 | +7.7 | +4.3 | +3.6 |
| **80** | +8.8 | +4.6 | +0.3 | -2.5 | -3.6 |
| **120** **(def)** | +3.6 | 0.0 | -2.7 | -5.0 | -6.0 |
| **150** | +2.1 | -1.6 | -4.7 | -6.5 | -7.3 |
| **200** | +0.2 | -3.6 | -5.9 | -7.8 | **-8.2** |

### 5.4.1 — geomean Δ% RSS vs 5.4.1 default `(s=262144, o=120)`

| o \ s | 131072 | 262144 | 524288 | 1048576 | 2097152 |
|---|---|---|---|---|---|
| **40** | -6.0 | -10.9 | **-15.6** | -15.3 | -10.9 |
| **80** | -0.9 | -5.2 | -8.5 | -8.0 | -3.0 |
| **120** **(def)** | +6.1 | 0.0 | -2.0 | -0.7 | +2.6 |
| **150** | +9.8 | +4.8 | +2.9 | +4.3 | +7.7 |
| **200** | +16.0 | +11.0 | +9.9 | +9.3 | +13.1 |

### Reading the four heatmaps together

- **Wall geomean shape is essentially the same for both runtimes.** `o=40` is uniformly the slowest column (more aggressive major-pacer hurts the typical bench by +10 to +20%); `o=200` with `s ≥ 1048576` is the fastest quadrant (-8 to -9%).
- **RSS geomean shape is also shared, but the magnitudes differ.** At `(s=524288, o=40)`: d8b -11.8%, 5.4 -15.6% — 5.4 cuts more RSS by going aggressive on `o`. This is the same story as the per-bench cross-version table below: at low-o cells, **5.4 reduces RSS more aggressively** than d8b does, so the d8b/5.4 RSS ratio is positive in that quadrant. The "off-heap pacer change" framing from 5-13 says this is the d8b pacer holding more RSS to amortise GC work — visible in the geomean.
- **The best balanced (Pareto) cell intra-d8b is `(s=1048576, o=80)`** with -3.8% wall AND -5.4% RSS — both improved. Same shape on 5.4 with the wall optimum slightly shifted to `o=40`. **No "ship a new default" candidate passes a 10% per-bench safety filter** on either runtime, because `devkit_gzip`'s tiny RSS baseline (17 MB) makes its percentage swing exceed 10% at most non-default cells. Drop the filter or whitelist `devkit_gzip` and `(s=1048576, o=80)` becomes the natural recommendation.

## Cross-version Pareto-frontier table — best d8b operating points (all 32 benches)

For each benchmark, the d8b cell minimising wall regression and the cell minimising RSS regression, side-by-side with the default `(s=262144, o=120)`. `wall%/RSS%` is d8b vs 5.4 at that cell — negative is d8b faster / smaller.

| benchmark | default | min-wall cell | min-RSS cell | available range |
|---|---|---|---|---|
| **owl_gc** | -37.2 / -18 | `(1048576, 150)`: **-41.6 / -16** | `(131072, 40)`: -37.4 / -19 | uniformly d8b win |
| **liq_parse_typecheck** | +5.9 / +3 | **`(262144, 40)`: -34.3 / -34** ✨ | same | strict win at low o |
| **zarith_pi** | +0.4 / +2 | `(131072, 40)`: **-27.3 / -18** | `(262144, 40)`: -16.1 / -24 | strict win at low o |
| **eio_fiber_stream** | +1.9 / -3 | **`(131072, 40)`: -16.4 / -21** ✨ | same | strict win at low (s, o) |
| **devkit_stre** | -3.7 / -4 | **`(262144, 40)`: -8.4 / -21** ✨ | same | strict win |
| **devkit_gzip** | -4.2 / -5 | **`(262144, 40)`: -8.9 / -11** ✨ | same | strict win |
| **ydump_repeat** | +1.2 / -7 | `(131072, 40)`: -7.4 / -16 | `(524288, 200)`: -0.8 / -24 | clear Pareto |
| **devkit_htmlstream** | -1.4 / -32 | `(524288, 40)`: -1.8 / -16 | `(2097152, 200)`: -1.6 / **-45** | RSS bottom -45% |
| **pplacer_testsuite** | +1.3 / -8 | `(1048576, 120)`: -3.6 / -5 | `(524288, 200)`: -0.8 / -9 | mostly negative |
| **sedlex_tokenize** | -2.5 / +4 | `(1048576, 120)`: -3.8 / +1 | `(2097152, 40)`: +2.2 / -14 | mixed |
| **test_decompress** | 0.0 / -10 | `(524288, 40)`: -4.0 / -7 | `(524288, 200)`: 0.0 / -25 | RSS-only |
| **devkit_network** | -1.0 / -22 | `(1048576, 200)`: -3.4 / -35 | `(131072, 200)`: -1.8 / -37 | both negative |
| **cpdf_blacktext** | +2.0 / -29 | `(2097152, 150)`: -0.8 / -28 | `(262144, 200)`: +2.5 / -35 | small wall, big RSS |
| **alt_ergo_unsat_smt2** | -0.1 / -25 | `(524288, 200)`: -0.2 / -44 | `(1048576, 200)`: -0.1 / **-45** | flat wall, big RSS |
| **menhir_ocamly** | -0.4 / +1 | `(524288, 40)`: -0.4 / -1 | `(2097152, 200)`: +0.9 / -3 | flat |
| **coqc_corelib_stress** | +1.7 / -0 | `(131072, 200)`: -3.2 / +0 | `(131072, 120)`: +3.2 / -0 | flat cross |
| **liq_video_frames_pool** | +1.7 / 0 | `(262144, 40)`: -0.8 / +1 | `(1048576, 150)`: 0.0 / 0 | flat |
| **lavyek_kv_2d** | +1.9 / -1 | `(2097152, 40)`: 0.0 / -2 | `(2097152, 200)`: +0.2 / -6 | flat |
| **lavyek_kv_4d** | +1.8 / -2 | `(2097152, 40)`: -0.6 / -1 | `(2097152, 200)`: +0.5 / -6 | flat |
| **lavyek_kv_8d** | +5.2 / -4 | `(2097152, 40)`: -5.1 / +1 | `(131072, 150)`: +0.8 / -6 | tune flips sign |
| **alt_ergo_yyll** | +2.5 / -11 | `(262144, 150)`: -0.8 / -18 | `(131072, 200)`: +0.5 / -27 | RSS-only |
| **irmin_mem_rw** | +3.3 / -28 | `(1048576, 80)`: -0.8 / -16 | `(262144, 200)`: +2.8 / **-46** | RSS-only |
| **menhir_sql_parser** | +4.2 / -5 | `(131072, 80)`: +1.6 / -8 | `(524288, 200)`: +1.7 / -29 | RSS room |
| **lavyek_kv_1d** | +3.9 / -5 | `(131072, 40)`: +2.7 / -3 | `(1048576, 200)`: +3.7 / -8 | small range |
| **cpdf_squeeze** | +3.8 / -26 | `(2097152, 150)`: +1.8 / -21 | `(131072, 200)`: +4.5 / **-42** | clear Pareto |
| **ocamlformat_rocq** | +4.6 / -10 | `(2097152, 40)`: +2.9 / -8 | `(524288, 200)`: +4.3 / **-40** | RSS room |
| **cpdf_scale** | +5.1 / -39 | `(2097152, 200)`: +1.5 / -48 | `(262144, 200)`: +4.7 / **-50** | bottom -50% RSS |
| **cpdf_merge** | +6.2 / -27 | `(2097152, 40)`: -0.4 / -10 | `(131072, 150)`: +5.3 / -35 | clear Pareto |
| **menhir_sysver** | +6.2 / -20 | `(131072, 40)`: +4.1 / -4 | `(1048576, 200)`: +5.8 / **-36** | RSS room |
| **alt_ergo_fill** | +8.7 / -22 | `(524288, 200)`: +5.3 / -27 | `(1048576, 200)`: +6.3 / -28 | small range |
| **ocamlc_self_compile** | +8.5 / -6 | `(1048576, 80)`: +6.9 / -5 | `(2097152, 120)`: +8.1 / -8 | sticky wall |
| **jsoo** | +16.1 / -20 | `(2097152, 40)`: +11.6 / -6 | `(524288, 200)`: +15.7 / **-38** | sticky wall |

## Intra-d8b best cell per bench — full suite

Per-bench cells that minimise wall and RSS *vs d8b at its own default cell*. The %s are intra-d8b — i.e. each bench's d8b value at the cell divided by that same bench's d8b value at default. The default cell is the reference point for every row.

| benchmark | default wall | min-wall cell | wall gain | min-RSS cell | RSS gain |
|---|---|---|---|---|---|
| **coqc_corelib_stress** | 17.22s | `(s=2097152, o=200)` | **-73.1%** | `(s=131072, o=40)` | -25.3% |
| **liq_parse_typecheck** | 9.46s | `(s=2097152, o=120)` | **-32.2%** | `(s=1048576, o=150)` | **-32.7%** |
| **zarith_pi** | 2.55s | `(s=2097152, o=40)` | **-25.5%** | `(s=2097152, o=150)` | **-65.8%** |
| **irmin_mem_rw** | 4.04s | `(s=2097152, o=120)` | -14.9% | `(s=524288, o=40)` | -17.9% |
| **owl_gc** | 3.40s | `(s=1048576, o=150)` | -9.4% | `(s=131072, o=200)` | -4.8% |
| **cpdf_scale** | 13.07s | `(s=2097152, o=200)` | -9.2% | `(s=524288, o=40)` | -23.3% |
| **ocamlformat_rocq** | 1.82s | `(s=1048576, o=200)` | -8.8% | `(s=524288, o=40)` | -21.6% |
| **liq_video_frames_pool** | 3.07s | `(s=1048576, o=200)` | -8.8% | `(s=1048576, o=200)` | -0.1% |
| **alt_ergo_fill** | 5.13s | `(s=1048576, o=200)` | -8.4% | `(s=1048576, o=40)` | -17.1% |
| **eio_fiber_stream** | 2.12s | `(s=2097152, o=40)` | -8.0% | `(s=262144, o=200)` | 0.0% |
| **cpdf_merge** | 2.22s | `(s=2097152, o=200)` | -7.7% | `(s=524288, o=40)` | -15.1% |
| **pplacer_testsuite** | 6.26s | `(s=2097152, o=120)` | -7.7% | `(s=131072, o=40)` | -6.0% |
| **cpdf_squeeze** | 3.52s | `(s=2097152, o=200)` | -7.4% | `(s=131072, o=40)` | -20.4% |
| **devkit_gzip** | 2.54s | `(s=131072, o=150)` | -7.1% | `(s=262144, o=200)` | -0.4% |
| **jsoo** | 3.75s | `(s=262144, o=200)` | -6.7% | `(s=131072, o=40)` | -16.0% |
| **menhir_sql_parser** | 1.25s | `(s=1048576, o=200)` | -6.4% | `(s=262144, o=40)` | -32.9% |
| **menhir_sysver** | 7.83s | `(s=524288, o=200)` | -6.3% | `(s=1048576, o=40)` | -5.7% |
| **ocamlc_self_compile** | 3.31s | `(s=1048576, o=200)` | -6.0% | `(s=1048576, o=40)` | -8.5% |
| **ydump_repeat** | 2.52s | `(s=524288, o=40)` | -5.6% | `(s=524288, o=150)` | -18.2% |
| **cpdf_blacktext** | 2.54s | `(s=2097152, o=200)` | -5.5% | `(s=1048576, o=40)` | -15.8% |
| **sedlex_tokenize** | 1.54s | `(s=131072, o=200)` | -4.5% | `(s=2097152, o=40)` | -16.2% |
| **lavyek_kv_8d** | 6.42s | `(s=262144, o=200)` | -3.6% | `(s=262144, o=40)` | -3.7% |
| **devkit_stre** | 4.12s | `(s=2097152, o=80)` | -3.4% | `(s=524288, o=200)` | -2.6% |
| **alt_ergo_yyll** | 6.45s | `(s=1048576, o=200)` | -3.4% | `(s=2097152, o=40)` | -13.6% |
| **lavyek_kv_4d** | 9.16s | `(s=524288, o=200)` | -2.1% | `(s=524288, o=40)` | -5.6% |
| **lavyek_kv_2d** | 15.20s | `(s=524288, o=200)` | -1.9% | `(s=524288, o=40)` | -4.9% |
| **test_decompress** | 1.71s | `(s=1048576, o=150)` | -1.8% | `(s=262144, o=200)` | -0.8% |
| **devkit_network** | 5.09s | `(s=262144, o=200)` | -1.8% | `(s=524288, o=40)` | -17.1% |
| **menhir_ocamly** | 12.68s | `(s=262144, o=200)` | -1.7% | `(s=1048576, o=120)` | -2.4% |
| **devkit_htmlstream** | 7.04s | `(s=2097152, o=200)` | -1.1% | `(s=262144, o=40)` | -10.5% |
| **lavyek_kv_1d** | 26.96s | `(s=262144, o=150)` | -1.0% | `(s=1048576, o=40)` | -3.8% |
| **alt_ergo_unsat_smt2** | 15.03s | `(s=262144, o=40)` | -0.1% | `(s=1048576, o=40)` | -31.4% |

## New cross-version findings — benches added vs the 5-13 subset

### `coqc_corelib_stress` — flat cross-version, dramatic intra-runtime

Both runtimes scale almost identically with `s` (every cross-version cell within ±3%
wall). But the intra-runtime tunability is enormous: d8b at `(s=2097152, o=200)` is
**-73.1% wall** vs d8b at default. The same picture holds for 5.4.1 (-72.7% wall at
the same cell). Coq is allocation-bandwidth-bound on this workload — going from a
256 KiB to 16 MiB minor heap quarters the wall time on both runtimes. The release
should NOT change the default for coq's benefit; this is a tuning recommendation
for coq-heavy users (set `s ≥ 1048576`).

intra-d8b wall vs default `(s=262144, o=120)`:

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +96.6 | +86.2 | +89.8 | +82.9 | +78.4 |
| **262144** **(def)** | +8.4 | +2.3 | 0.0 | -1.5 | -4.4 |
| **524288** | -31.5 | -39.7 | -41.4 | -42.9 | -43.7 |
| **1048576** | -54.4 | -60.2 | -62.5 | -63.5 | -64.2 |
| **2097152** | -58.6 | -67.0 | -72.1 | -72.8 | **-73.1** |

cross-version wall (d8b/5.4):

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +0.4 | +1.2 | +3.2 | -0.5 | -3.2 |
| **262144** **(def)** | -0.1 | -0.4 | +1.7 | +0.5 | -2.1 |
| **524288** | +0.4 | +1.4 | +0.9 | +0.9 | +0.3 |
| **1048576** | -0.1 | +1.2 | -0.5 | -1.4 | -1.3 |
| **2097152** | -0.1 | +9.0 | -1.4 | -0.4 | +1.5 |

(The `(s=2097152, o=80)` +9.0% is a single-cell artifact — neighbours are all near 0; within-cell spread on that one cell is 11% — borderline noise.)

### `eio_fiber_stream` — strict cross-version win at low (s, o)

cross-version wall (d8b/5.4):

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | **-16.4** | -1.7 | +1.8 | 0.0 | +1.8 |
| **262144** **(def)** | -10.7 | -2.8 | +1.9 | +1.0 | -1.4 |
| **524288** | -2.9 | -1.0 | +1.0 | -2.0 | 0.0 |
| **1048576** | -1.0 | +1.5 | +2.6 | +0.5 | +3.0 |
| **2097152** | -0.5 | +1.5 | 0.0 | +2.6 | -0.5 |

d8b wins at the entire `o=40` column (-1 to -16%) and loses in the `o=120-150` band by a few percent. The default-cell +1.9% headline understates a clean win that's available at low o. The Effect.perform/Suspend hot path in Eio benefits from a tighter major-pacer cycle on d8b.

### `alt_ergo_unsat_smt2` — RSS Pareto, neutral wall

cross-version RSS (d8b/5.4):

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | -4.1 | -11.9 | -19.6 | -27.1 | -37.2 |
| **262144** **(def)** | -6.6 | -14.7 | -25.5 | -32.8 | -42.0 |
| **524288** | -7.5 | -18.6 | -28.7 | -35.0 | -44.3 |
| **1048576** | -7.7 | -18.9 | -27.9 | -34.9 | **-45.0** |
| **2097152** | -7.8 | -17.5 | -26.5 | -33.8 | -43.2 |

Wall is flat across the grid (every cell within ±2% — values omitted; the row spread is 1.5%-3.0% within-cell). RSS scales monotonically with `o`: at `o=200, s ≥ 524288` d8b uses **-44 to -45% RSS** vs 5.4. This is the largest RSS Pareto in the full suite, alongside cpdf_scale (-50%). alt_ergo_unsat_smt2 sweeps the SIGVTALRM-armed solver loop on a hard SMT input; the weak-hashset (Weak.Make) population is structurally larger on 5.4 because its pacer holds promoted blocks longer.

### `irmin_mem_rw` — intra-d8b only

The cross-version effect is mild (+3.3% wall, -28% RSS at default; min-wall cell `(1048576, 80)`: -0.8 / -16). The intra-d8b view shows clean improvement with larger `s`:

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +31.7 | +17.1 | +12.6 | +10.6 | +9.7 |
| **262144** **(def)** | +10.9 | +2.7 | 0.0 | -0.5 | -1.0 |
| **524288** | -1.2 | -5.9 | -7.4 | -7.7 | -8.7 |
| **1048576** | -8.9 | -11.1 | -12.1 | -10.9 | -12.6 |
| **2097152** | -12.6 | -14.6 | **-14.9** | -14.1 | -14.6 |

Lwt-heavy workloads on irmin's in-memory backend benefit substantially from `s ≥ 1048576` on d8b alone — the bind-chain allocation profile fits the bigger nursery better.

### `lavyek_kv_8d` — only kv suite cell whose default cross-version is regressed

Cross-version at default `(s=262144, o=120)`: +5.2% / -4.3%. Most of the kv suite is
flat at default (+1.8 to +1.9% for 2d, 4d; +3.9% for 1d). 8d's regression flips
sign at `(s=2097152, o=40)` → -5.1% wall. Intra-d8b: best at `(s=262144, o=200)`
→ -3.6% wall, ~flat RSS. The 8-domain cell is more pacer-sensitive than the
others because the per-domain minor-heap budget is divided 8 ways and goes through
the work-stealing more.

intra-d8b wall:

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +12.3 | +5.9 | +1.7 | -1.7 | -2.8 |
| **262144** **(def)** | +5.6 | +4.4 | 0.0 | 0.0 | **-3.6** |
| **524288** | +7.0 | +2.0 | -2.6 | -2.5 | -1.1 |
| **1048576** | +5.9 | +3.0 | +1.4 | -2.6 | -0.2 |
| **2097152** | +4.4 | +5.0 | +1.1 | +2.6 | -2.5 |

### `devkit_gzip` — quiet cross-version d8b win

cross-version wall (d8b/5.4):

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | -8.2 | -8.3 | -6.2 | -1.7 | +10.3 |
| **262144** **(def)** | **-8.9** | -5.5 | -4.2 | +8.8 | -1.2 |
| **524288** | +5.0 | +1.5 | -0.7 | +9.1 | +1.2 |
| **1048576** | +3.7 | +4.6 | +3.3 | +4.1 | +2.9 |
| **2097152** | +2.9 | +2.5 | +1.6 | +0.4 | +2.0 |

d8b wins at small s, low o; loses at large s. The +9% at `(524288, 150)` is a single-cell artifact (within-cell wall spread 6.3% — neighbours are +1 to +9). Wall baseline is tiny (~2.5s) so the cross-version effect is ~225ms.

## Reflection vs the 5-13 sweep

Five new findings from the full-suite extension:

| bench | 5-13 status | 5-16 (full-suite) status | new in 5-16 |
|---|---|---|---|
| `coqc_corelib_stress` | not in subset | cross flat; intra -73% wall at large s | dramatic intra-runtime axis |
| `eio_fiber_stream` | not in subset | cross -16% wall at (131072, 40) | strict d8b win at low (s, o) |
| `alt_ergo_unsat_smt2` | not in subset | cross -45% RSS at (1048576, 200) | largest RSS Pareto in suite |
| `alt_ergo_yyll` | not in subset | cross flat wall, -27% RSS | small RSS Pareto |
| `irmin_mem_rw` | not in subset | intra -15% wall at large s | clean Lwt intra-d8b finding |
| `devkit_gzip` | not in subset | cross -8.9% wall at low o | quiet d8b winner |
| `lavyek_kv_*d` | not in subset (1d/2d/4d): flat; 8d: +5% | confirms parallel-suite sensitivity to s and 8d's tuning-recoverable regression | new parallel-suite data |
| `menhir_ocamly` / `_sql_parser` | not in subset | cross flat to slight d8b loss; small Pareto room | confirms 5-13's `menhir_sysver`-only framing was incomplete; the other two menhir cells are quieter |
| `test_decompress`, `ydump_repeat`, `sedlex_tokenize` | not in subset | cross flat to slight d8b win; modest RSS Pareto | added baseline for these benches |

Confirmation findings on the 13 5-13 benches (default-cell cross-version effects, N=5 vs N=3):

| bench | 5-13 default | 5-16 default | Δ |
|---|---|---|---|
| `liq_parse_typecheck` | +6.6 / +2.5 | +5.9 / +3 | -0.7pp wall, +0.5pp RSS |
| `jsoo` | +15.8 / -19.8 | +16.1 / -20 | +0.3pp wall |
| `alt_ergo_fill` | +8.4 / -20.2 | +8.7 / -22 | +0.3pp wall |
| `ocamlc_self_compile` | +9.6 / -3.3 | +8.5 / -6 | -1.1pp wall |
| `menhir_sysver` | +5.6 / -19.7 | +6.2 / -20 | +0.6pp wall |
| `cpdf_merge` | +4.9 / -27.2 | +6.2 / -27 | +1.3pp wall |
| `cpdf_scale` | +5.4 / -39.4 | +5.1 / -39 | -0.3pp wall |
| `cpdf_squeeze` | +3.9 / -26.2 | +3.8 / -26 | -0.1pp wall |
| `ocamlformat_rocq` | +4.7 / -15.7 | +4.6 / -10 | flat wall, -5.7pp RSS |
| `pplacer_testsuite` | +2.3 / -7.6 | +1.3 / -8 | -1.0pp wall |
| `zarith_pi` | +4.1 / +2.6 | +0.4 / +2 | -3.7pp wall* |
| `liq_video_frames_pool` | +1.0 / +0.5 | +1.7 / 0 | +0.7pp wall |
| `devkit_stre` | -3.5 / -4.3 | -3.7 / -4 | flat |

\* `zarith_pi` at default shrunk from +4.1% to +0.4% — the within-cell wall spread at default on N=3 was 7.4%, suggesting the 5-13 estimate was on the high side of the cell's distribution. N=5 puts the default-cell wall effect within 1pp of zero. The intra-d8b "s ≥ 1048576 collapses the o axis" finding from 5-13 reproduces unchanged.

## Methodology notes

- **Median over mean**, N=5 per cell. All 1600 cells captured 5/5.
- **Within-cell wall spread** ((max−min)/median) computed on the 1600 medians: mean **2.0%**, median **1.3%**. Cells with ≥15% spread: 26 of 1600 — concentrated on `coqc_corelib_stress` low-s cells (warmup-noise on a long compile) and `liq_video_frames_pool` small-batch cells, consistent with the 5-13 caveats.
- **Olly missing-events artifact on lavyek_kv_*d**: 15 invocations across the 200 lavyek cells reported a wall time of approximately -4.7M seconds (with the matching +4.7M in CPU time). **Root cause: missing runtime_events.** Two evidence threads:
  1. **14 of 15 bad invocations have `len(domain_stats) == 1`** in the JSON sidecar — i.e. olly only saw the main domain's begin/end markers; the worker domains' stats blocks are entirely absent (expected 2, 4, or 8). The 15th case (`lavyek_kv_2d d8b s=131072 o=200 inv #2`) has 2/2 domain_stats but domain 0's wall_time is the missing-events sentinel — its begin event was lost.
  2. **The -4.7M-second magnitude matches system uptime.** Host uptime at run time was 54d 14:25 = 4,717,500 s; the bad-invocation values cluster within ±2000 s of that. olly's fallback when a domain's begin event is missing is `now − boot_time` rather than `now − begin_event`, producing the sentinel. The negative sign comes from the aggregation `min(domain_wall)` propagating the bogus value with a sign flip in olly's accounting.
  3. Confirming evidence: bad invocations also under-count `allocations.total_heap` (e.g. `lavyek_kv_1d s=131072 o=80 inv #1`: 494M alloc + 3940 minor collections, vs 2.37B + 18,500 in the same cell's good invocations — ~21% of events captured, ~79% dropped to ring overflow).

  **Trigger.** The full_s_o_sweep_2026_05_16.yml config string was `ocaml-X|perf_grp1|re-25|md-2` without the `re_par|md_par|pin_lavyek` modifiers. The base config's `lavyek_only_excludes` mechanism correctly skipped applying `re-25|md-2` to the lavyek suite — but no replacement was supplied, so lavyek ran with **olly's default 8 MB per-domain ring** (e=23). At 10M-op × 8 domains the ring overflows, dropping the worker-domain begin/end events.

  **Impact on this report.** All bad invocations sit at most 1-of-5 per cell except `lavyek_kv_4d 5.4.1 (524288, 40)` which has 2-of-5 bad. Medians are robust to ≤2/5 outliers, so the lavyek numbers above are unaffected.

  **Fix for the next sweep.** Append `|re_par|md_par|pin_lavyek` to both config-string entries — this enables the `e=22, d=8` per-domain ring (32 MB total per domain) that the base config defines for the parallel suite, and the `taskset -c 0-15` wrapper. Worth filing the missing-events fallback (`now − boot_time` instead of dropping the invocation or zeroing the wall) as a separate [runtime_events_tools issue](https://github.com/tarides/runtime_events_tools).
- **All 1600 cells captured** — no missing data, no OOMs, no timeouts.
- **Trade-off visualization**: the four overall-picture geomean heatmaps in §"Cross-version geomean overall picture" use the new feature added to notebook
  [C_gc_parameter_sweep.ipynb](../../running-ng/notebooks/C_gc_parameter_sweep.ipynb)
  §3 — each cell shows the geomean Δ% across the 32 benchmarks vs the runtime's own default cell. Same shape as the §5 cross-runtime aggregate heatmap; the notebook automatically stars the cell minimising each geomean.

## Suggested follow-ups

1. **Re-run the (M, o) sweep at N=5 against the full suite** so the off-heap-pacer story can be told at the same resolution as this (s, o) one. The 5-13 (M, o) sweep was N=3 on 8 benches; lifting it to N=5 × 32 benches takes the same wall-budget as this run (~6h on monolith).
2. **Fix the lavyek modifier config for the next sweep.** Root cause is now known: the config string omitted `re_par|md_par|pin_lavyek`, so lavyek ran with the default 8 MB ring instead of the per-domain 32 MB ring the parallel suite needs. Append those three modifiers to the config strings in `full_s_o_sweep_2026_05_16.yml` (or any successor) and re-run only the affected lavyek cells to fill the missing-events tail. Separately, file an upstream issue against [runtime_events_tools](https://github.com/tarides/runtime_events_tools) asking olly to either zero the wall or drop the invocation when a domain's begin event is lost, rather than falling back to `now − boot_time`.
3. **Whitelist `devkit_gzip` for the safety filter** in notebook §4 (Q3 candidates). Its 17 MB RSS baseline makes every non-default cell exceed a 10% absolute filter; either drop it from the safety check or use an absolute-MB threshold for tiny-RSS benches.
4. **Investigate the `(s=1048576, o=80)` ship-candidate further.** On the full-suite geomean view this is the best balanced cell intra-d8b (-3.8% wall, -5.4% RSS). The worst-bench regressions there are `jsoo` (+11.5% wall, sticky from 5-12 analysis) and `devkit_gzip` (+41% RSS, but only ~7 MB absolute). Worth a focused N=10 run at that single cell to characterise the worst-bench tail.
5. **Repro `eio_fiber_stream`'s low-(s, o) cross-version d8b win on a richer Eio workload** (the current bench is a 32 MB single-fiber stream — the win may not survive on a real Eio service). If it survives, this is a small but clean win to call out in release notes.
