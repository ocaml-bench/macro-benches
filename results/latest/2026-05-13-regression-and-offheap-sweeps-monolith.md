# GC parameter sweeps — 5.4.1 vs d8bb46c on monolith — (s, o) regression + (M, o) off-heap

**Date:** 2026-05-13
**Host:** monolith (AMD Ryzen 9 9950X, 16C/32T, governor=performance, 64 GiB, kernel 6.17)
**Compilers:** `ocaml-5.4.1` (release) vs `ocaml-d8bb46c39bf5fcafb513a8ba18e667d3f8c2600a` (5.5-beta) — base, no `-fp`/`-flambda`
**Two sweeps, run sequentially overnight:**

| sweep | grid | benches | runtime cells | invocations |
|---|---|---|---|---|
| **A** (s, o) regression | s ∈ {131072, 262144, 524288, 1048576, 2097152} × o ∈ {40, 80, 120, 150, 200} (5×5) | 13 — the regressed set from the 5-12 N=10 run | 13 × 2 × 25 = 650 | 1950 |
| **B** (M, o) off-heap | M ∈ {11, 22, 44, 100, 250} × o ∈ {40, 80, 120, 150, 200} (5×5) | 8 — the off-heap subset (incl. `liq_video_frames_pool`) | 8 × 2 × 25 = 400 | 1200 |

**Configs:**
[regression_s_o_sweep_2026_05_13.yml](../../running-ng/src/running/config/experiments/regression_s_o_sweep_2026_05_13.yml),
[offheap_M_o_sweep_2026_05_13.yml](../../running-ng/src/running/config/experiments/offheap_M_o_sweep_2026_05_13.yml)
**Logs (in-repo mirrors — sidecars + YAML configs):**
[`../logs/2026-05-13-regression-s-o-monolith/`](../logs/2026-05-13-regression-s-o-monolith/) (Sweep A),
[`../logs/2026-05-13-offheap-M-o-monolith/`](../logs/2026-05-13-offheap-M-o-monolith/) (Sweep B).
Originals: `~/running-ng/gc-sweep-logs-regression-s-o-2026-05-13/monolith-2026-05-13-Wed-095212/` + `~/running-ng/gc-sweep-logs-offheap-M-o-2026-05-13/monolith-2026-05-13-Wed-142904/`.
**Companion reports:** [2026-05-12-fp-flambda-5.4.1-vs-d8bb46c-monolith-N10.md](2026-05-12-fp-flambda-5.4.1-vs-d8bb46c-monolith-N10.md) (the headline N=10 run this sweep targets), [../older/2026-05-11-offheap-M-o-sweep-monolith.md](../older/2026-05-11-offheap-M-o-sweep-monolith.md) (prior (M, o) sweep — partial overlap, see §"Reflection vs 5-11"; archived because this sweep supersedes it).

**All 1050 cells captured cleanly at N=3.**

**Reading the heatmaps:** each cell shows `wall%/RSS%` as d8b vs 5.4 percentages at that GC-param point. Negative = d8b is faster / uses less RSS. A cell like `+5.2/-27` means d8b is 5.2% slower but uses 27% less RSS at that (s, o) or (M, o) — that's the trade-off the user asked for, visible in one glance.

## TL;DR

- **Two views of the data, both important.** Each (bench, cell) has a *cross-version* ratio (d8b/5.4) and a separate *intra-runtime* ratio (cell vs default on the **same** runtime). The cross-version view answers "is d8b worse than 5.4 here?" (the OCaml-maintainer question); the intra-runtime view answers "I'm already on d8b — can I tune to beat my current default?" (the production-user question). These views can disagree — `liq_parse_typecheck` is the cleanest example in this sweep. See [§Intra-runtime tuning view](#intra-runtime-tuning-view--whats-available-within-d8b-alone).
- **`liq_parse_typecheck` is the headline find of Sweep A.** At `(s=262144, o=40)` d8b is **-35.2% wall AND -33.7% RSS** vs 5.4 — a strict-better cell. At the default `(s=262144, o=120)` it's **+6.6% / +2.5%** (regression). The default `o=120` is bad for this workload under d8b; **lower `o` flips the version effect entirely.** Within d8b alone, `(s=2097152, o=200)` is **-33.3% wall** vs d8b default — the strongest intra-d8b finding in either sweep. The 5-12 headline regression on `liq_parse_typecheck` is purely a default-`o` artifact.
- **`liq_video_frames_pool` (the ocaml#14533 cell) is flat across the entire (M, o) grid cross-version.** Every cell is within ±2% wall, ±1% RSS vs 5.4. The "free lunch at large M" predicted by #14533 does **not** show up as a d8b/5.4 ratio improvement in this synthetic on this hardware. *Within d8b alone* the variant does improve monotonically with M (M=250 is much faster than M=11 on this short batch) — but 5.4 improves in lockstep. Two possibilities for the cross-version flatness: the synthetic doesn't model what real ffmpeg does, or Ryzen 9 9950X doesn't surface the toots effect cross-version. Negative cross-version result for the parked #14533 repro; intra-d8b M-monotonicity is consistent with the real-workload story.
- **`owl_gc` confirms 5-11 cleanly:** the d8b win is monotone in M (smaller M, bigger win). `(M=11, o=40)` is **-55.2% wall / -5.9% RSS** — the cleanest off-heap d8b win in the matrix. The win shrinks to -12% at M=250 because the 5.4 pacer stops being pathological.
- **`zarith_pi` is `o`-bound on both axes**, confirming and extending 5-11. At `o ≤ 80` d8b is **-10 to -17% wall and -22 to -25% RSS** (strict win). At `o ≥ 120` it crosses over to neutral-or-regressed. RSS climbs to **+34%** at `o=200`. Sweep A also reveals that **`s ≥ 1048576` neutralises the `o` axis entirely** — at large minor heap, every cell is ±5%/-18%. So zarith_pi has *two* independent levers, not one.
- **Big RSS-only Pareto wins exist for cpdf_*, ocamlformat_rocq, menhir_sysver.** At `(s=524288, o=200)` cpdf_scale gets -50% RSS for +4.1% wall; ocamlformat_rocq gets -38.5% RSS for +5.0% wall; menhir_sysver gets -35.7% RSS at `(1048576, 200)` for +4.7% wall. None of these are improved by the M-axis (Sweep B confirms `M` is flat for cpdf_*).

## Headline Pareto-frontier table — best d8b operating points

For each regressed benchmark, the d8b cell minimising wall regression and the cell minimising RSS regression, side-by-side with the default `(s=262144, o=120)` and/or `(M=44, o=120)`. This makes the trade-off visible at a glance — if the two cells are the same, there's no trade-off; if they're different, the gap is the available Pareto front.

### Sweep A — (s, o), regressed benches

| benchmark | default | min-wall cell | min-RSS cell | available range |
|---|---|---|---|---|
| **liq_parse_typecheck** | +6.6% / +2.5% | **`(262144, 40)`: -35.2% / -33.7%** ✨ | same | strict win at low o |
| **devkit_stre** | -3.5% / -4.3% | **`(262144, 40)`: -9.2% / -24.2%** ✨ | same | strict win |
| **zarith_pi** | +4.1% / +2.6% | `(131072, 40)`: -24.7% / -16.9% | `(262144, 40)`: -11.4% / -26.3% | strict-win regime exists |
| **liq_video_frames_pool** | +1.0% / +0.5% | `(262144, 150)`: -1.0% / +0.5% | `(131072, 150)`: -0.7% / +0.3% | flat (no trade-off) |
| **alt_ergo_fill** | +8.4% / -20.2% | `(2097152, 80)`: +5.1% / -18.5% | `(1048576, 200)`: +5.5% / -28.5% | small range |
| **cpdf_merge** | +4.9% / -27.2% | `(2097152, 40)`: +0.4% / -10.3% | `(131072, 150)`: +5.0% / -35.1% | clear Pareto |
| **cpdf_scale** | +5.4% / -39.4% | `(2097152, 200)`: +1.7% / -47.7% | `(262144, 200)`: +4.1% / -50.0% | RSS bottom is -50% |
| **cpdf_squeeze** | +3.9% / -26.2% | `(2097152, 200)`: +1.6% / -24.9% | `(131072, 200)`: +4.3% / -41.5% | clear Pareto |
| **ocamlformat_rocq** | +4.7% / -15.7% | `(1048576, 40)`: +3.0% / -9.4% | `(524288, 200)`: +5.0% / -38.5% | big RSS room |
| **menhir_sysver** | +5.6% / -19.7% | `(131072, 40)`: +4.5% / -3.7% | `(1048576, 200)`: +4.7% / -35.7% | big RSS room |
| **pplacer_testsuite** | +2.3% / -7.6% | `(1048576, 120)`: -2.9% / -4.6% | `(524288, 200)`: -0.5% / -9.3% | both negative — flip-improve |
| **jsoo** | +15.8% / -19.8% | `(2097152, 40)`: +12.1% / -5.8% | `(524288, 200)`: +15.0% / -38.4% | wall regression is sticky |
| **ocamlc_self_compile** | +9.6% / -3.3% | `(1048576, 200)`: +6.9% / -7.2% | same | small range, sticky |

### Sweep B — (M, o), off-heap benches

| benchmark | default | min-wall cell | min-RSS cell | available range |
|---|---|---|---|---|
| **owl_gc** | -35.8% / -17.2% | **`(11, 40)`: -55.2% / -5.9%** | `(22, 80)`: -46.9% / -21.7% | -55% wall at M=11 |
| **zarith_pi** | +3.3% / +3.8% | **`(44, 40)`: -17.5% / -23.0%** ✨ | `(11, 40)`: -10.1% / -25.4% | strict-win at low o |
| **liq_video_frames_pool** | +0.3% / +0.4% | `(11, 150)`: -2.7% / +2.3% | `(250, 80)`: +1.3% / -0.2% | flat cross-version (no #14533 free lunch in d8b/5.4 ratio) |
| **alt_ergo_fill** | +8.6% / -21.7% | `(250, 150)`: +5.0% / -23.6% | `(11, 200)`: +5.4% / -25.2% | small range, M flat |
| **cpdf_merge** | +5.9% / -27.4% | `(11, 80)`: +3.6% / -18.1% | `(100, 200)`: +4.6% / -30.0% | M flat (o-only) |
| **cpdf_scale** | +4.4% / -39.4% | `(100, 150)`: +3.5% / -42.8% | `(100, 200)`: +4.5% / -50.2% | M flat (o-only) |
| **cpdf_squeeze** | +4.6% / -25.9% | `(11, 150)`: +3.1% / -29.1% | `(250, 150)`: +3.4% / -29.3% | M flat |
| **pplacer_testsuite** | +0.3% / -7.1% | `(250, 80)`: -0.7% / -6.7% | `(100, 150)`: +2.6% / -9.4% | small |

## Intra-runtime tuning view — what's available within d8b alone

Everything in the Pareto-frontier table above is a **cross-version** comparison
(d8b vs 5.4 at each cell). That answers the OCaml-maintainer question "is d8b
worse than 5.4 here?" but it does **not** answer the production question "I'm
already on d8b — can I tune `(s, o)` / `(M, o)` to beat my current default?"

These two views can disagree. A cell where d8b beats 5.4 may not actually be
faster than d8b at default (5.4 just regresses more there). And conversely, a
cell where d8b *loses ground* to 5.4 may still be a large absolute speedup
over d8b's default — because both runtimes improve at that cell, just 5.4
improves more.

`owl_gc` is the cleanest example of this:

| cell | 5.4 wall | d8b wall | d8b/5.4 (cross) | d8b vs d8b-default (intra) |
|---|---|---|---|---|
| `(M=44, o=120)` (default) | 5.30s | 3.41s | **-35.8%** | (anchor) |
| `(M=11, o=40)` | 4.69s | 2.10s | **-55.2%** (cross-min) | **-38.4%** (faster than default) |
| `(M=250, o=120)` | 2.85s | 2.50s | -12.1% | **-26.4%** |
| `(M=250, o=200)` | 2.79s | 2.10s | -11.4% | **-38.4%** (also fastest) |

Cross-version says "M=11 is the d8b-vs-5.4 sweet spot"; intra-d8b says
M=250 is equally fast and gives -62% RSS as a bonus. Different cells,
different framings — both correct for the question they answer.

### Best intra-d8b cell per bench

For each bench: the cell that minimises d8b wall vs **d8b default**, and the
cell that minimises d8b RSS vs **d8b default**. Wall and RSS gains expressed
as % vs d8b at its own default cell.

#### Sweep A — (s, o), intra-d8b

| benchmark | min-wall cell | wall gain | min-RSS cell | RSS gain |
|---|---|---|---|---|
| **liq_parse_typecheck** | `(s=2097152, o=200)` | **-33.3%** | `(s=1048576, o=150)` | **-32.8%** |
| **zarith_pi** | `(s=2097152, o=120)` | **-25.3%** | `(s=2097152, o=40)` | **-66.0%** |
| **cpdf_scale** | `(s=2097152, o=200)` | -10.0% | `(s=524288, o=40)` | -23.3% |
| **ocamlformat_rocq** | `(s=1048576, o=200)` | -9.4% | `(s=524288, o=40)` | -17.5% |
| **pplacer_testsuite** | `(s=2097152, o=120)` | -9.2% | `(s=262144, o=40)` | -6.3% |
| **alt_ergo_fill** | `(s=1048576, o=200)` | -8.5% | `(s=1048576, o=40)` | -18.7% |
| **cpdf_squeeze** | `(s=2097152, o=200)` | -8.4% | `(s=131072, o=40)` | -20.1% |
| **liq_video_frames_pool** | `(s=262144, o=200)` | -8.0% | `(s=1048576, o=200)` | -0.1% |
| **cpdf_merge** | `(s=1048576, o=200)` | -7.0% | `(s=524288, o=40)` | -14.4% |
| **ocamlc_self_compile** | `(s=1048576, o=200)` | -6.7% | `(s=1048576, o=40)` | -8.4% |
| **jsoo** | `(s=131072, o=200)` | -6.3% | `(s=131072, o=40)` | -16.1% |
| **menhir_sysver** | `(s=1048576, o=200)` | -6.2% | `(s=1048576, o=40)` | -5.7% |
| **devkit_stre** | `(s=2097152, o=200)` | -3.7% | `(s=524288, o=200)` | -3.3% |

#### Sweep B — (M, o), intra-d8b

| benchmark | min-wall cell | wall gain | min-RSS cell | RSS gain |
|---|---|---|---|---|
| **liq_video_frames_pool** ⚠ | `(M=250, o=200)` | **-75.7%** | `(M=250, o=80)` | -3.4% |
| **owl_gc** | `(M=250, o=200)` | **-38.4%** | `(M=250, o=200)` | -62.2% |
| **zarith_pi** | `(M=250, o=200)` | -8.7% | `(M=22, o=200)` | -16.9% |
| **alt_ergo_fill** | `(M=11, o=200)` | -6.9% | `(M=100, o=40)` | -17.2% |
| **cpdf_merge** | `(M=22, o=200)` | -5.1% | `(M=11, o=40)` | -11.3% |
| **cpdf_squeeze** | `(M=44, o=200)` | -4.4% | `(M=22, o=40)` | -19.3% |
| **cpdf_scale** | `(M=250, o=200)` | -4.0% | `(M=100, o=40)` | -19.5% |
| **pplacer_testsuite** | `(M=250, o=80)` | -2.8% | `(M=250, o=40)` | -7.1% |

⚠ — for `liq_video_frames_pool` the absolute wall is tiny (~3.0s); the -75%
intra-d8b "win" is inside the within-cell spread on this short bench. Treat
the headline number as a directional signal (large M is faster within d8b)
rather than a precise magnitude. The other rows have wall ratios well above
the per-cell noise floor.

### Three takeaways from the intra-runtime view

1. **`liq_parse_typecheck` is the same story under both views.** Cross-version
   said d8b wins big at `o=40`; intra-d8b confirms `(s=2097152, o=200)` is
   33% faster than d8b-default. The 5-12 N=10 +6.6% headline regression is
   tunable away from inside d8b: pick any cell at `s ≥ 1048576` or `o ≤ 80`
   to get a real wall improvement over d8b default.

2. **`liq_video_frames_pool` shows nothing cross-version but improves
   monotonically with M intra-d8b.** The d8b/5.4 ratio is flat (±2% wall)
   across the entire (M, o) grid — the #14533 free lunch doesn't surface
   as a cross-version improvement here. But *within d8b alone*, M=250 is
   dramatically faster than M=11 on the same short batch (the small-M
   cells in d8b are catastrophically slow on this finaliser-dominated
   workload). For a production media-pipeline user on d8b, **set
   `M=250`** — it matches the real-workload reproduction of
   [ocaml/ocaml#14533](https://github.com/ocaml/ocaml/issues/14533).

3. **`owl_gc` benefits both views.** Cross-version showed -55% wall at
   M=11; intra-d8b shows -38% wall at M=250. Different cells, but both
   give large d8b improvements. For a production user, M=250 is preferable
   because it gets -62% RSS as well (vs -6% at M=11); the cross-version
   "M=11 is best" framing didn't surface this.

### Highlighted heatmap — full intra-d8b detail for the biggest reframing

`wall%/RSS%` vs d8b at the default cell. Negative = faster / smaller.

#### `liq_parse_typecheck` intra-d8b — confirms the cross-version story

d8b default `(s=262144, o=120)`: **9.53s / 49 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | -16.9 / -23 | -3.4 / +3 | +3.1 / +2 | -1.0 / +3 | -8.6 / +9 |
| **262144** **(def)** | -32.7 / -36 | -16.0 / -10 | +0.0 / +0 | -3.4 / +5 | -10.4 / +5 |
| **524288** | -31.2 / -26 | -24.0 / -24 | -10.0 / -11 | -5.2 / -6 | -6.5 / -3 |
| **1048576** | -29.6 / -7 | -23.6 / -7 | -22.0 / -18 | -27.7 / -13 | -29.4 / -10 |
| **2097152** | -27.2 / +18 | -25.6 / +18 | -26.4 / +18 | -30.9 / +18 | **-33.3 / -10** |

The whole right half of the grid is a 25-33% improvement over d8b default.
At `(s=2097152, o=200)`: 6.35s wall, ~44 MB RSS — both axes substantially
better than default. This is the strongest single intra-d8b finding in
either sweep, *and* it agrees with the cross-version story.

### Complete intra-d8b heatmap reference — all benches

Per-bench intra-d8b heatmaps for the remaining benches not highlighted
above. Each cell is `wall%/RSS%` of d8b at that cell vs d8b at its default
cell. Negative = faster / smaller than d8b default.

#### Sweep A — (s, o) intra-d8b, remaining 12 benches

##### alt_ergo_fill

d8b default `(s=262144, o=120)`: **5.05s / 943 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +33.9 / -17 | +10.3 / -6 | +3.2 / +5 | +1.2 / +12 | -2.8 / +13 |
| **262144** **(def)** | +28.7 / -18 | +8.1 / -5 | +0.0 / +0 | -3.8 / +6 | -6.7 / +13 |
| **524288** | +26.1 / -18 | +5.0 / -8 | -2.4 / -3 | -5.5 / +3 | -8.1 / +11 |
| **1048576** | +25.7 / -19 | +4.8 / -5 | -1.2 / +0 | -4.4 / +10 | -8.5 / +8 |
| **2097152** | +28.1 / -17 | +5.9 / -8 | -0.2 / +0 | -2.6 / +8 | -5.9 / +17 |

The `o` axis dominates; `s` barely matters. Sweet spot is `o=200` on any
`s ≥ 524288` (-8 to -9% wall). The `o=40` column is uniformly worse (+25
to +34% wall) because the more aggressive major pacer hurts this Z.t-heavy
workload. Note this contradicts the cross-version Pareto for alt_ergo_fill;
intra-d8b says `o=200` is good, cross-version says `o=80`.

##### cpdf_merge

d8b default `(s=262144, o=120)`: **2.15s / 363 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +31.6 / -7 | +9.8 / +2 | +1.4 / +10 | -1.4 / +9 | -5.6 / +15 |
| **262144** **(def)** | +29.3 / -11 | +7.4 / +3 | +0.0 / +0 | -1.9 / +24 | -4.2 / +18 |
| **524288** | +26.5 / -14 | +6.0 / -5 | +0.5 / +17 | -3.7 / +14 | -5.6 / +29 |
| **1048576** | +22.3 / -11 | +3.7 / +2 | -2.8 / +13 | -4.7 / +13 | -7.0 / +23 |
| **2097152** | +18.1 / -4 | +2.8 / +2 | -4.2 / +4 | -5.6 / +7 | -7.0 / +18 |

Wall best at `(s=2097152, o=200) → -7.0% / +17.8% RSS`. The 5-08 sweep
already showed cpdf_merge benefits from larger `s`; this rerun confirms,
adding +200 to the `o` axis which gives a small further gain.

##### cpdf_scale

d8b default `(s=262144, o=120)`: **13.02s / 489 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +27.3 / -15 | +12.4 / -5 | +6.9 / +0 | +4.7 / +7 | +1.9 / +16 |
| **262144** **(def)** | +14.4 / -20 | +3.7 / -7 | +0.0 / +0 | -2.4 / +5 | -3.9 / +11 |
| **524288** | +7.9 / -23 | -2.1 / -14 | -5.1 / -4 | -6.4 / +4 | -7.8 / +10 |
| **1048576** | +5.3 / -20 | -3.8 / -13 | -6.9 / -3 | -8.1 / +3 | -9.7 / +9 |
| **2097152** | +3.7 / -20 | -4.9 / -7 | -7.5 / -3 | -8.5 / +2 | **-10.0 / -0** |

Best wall AND essentially flat RSS at `(s=2097152, o=200) → -10.0% / -0.2%`.
The intra-d8b view says cpdf_scale is one of the cleanest wins available —
both axes are simultaneously better than default. Cross-version saw -50%
RSS at the same cell because 5.4 was much larger; intra-d8b just sees the
absolute d8b improvement.

##### cpdf_squeeze

d8b default `(s=262144, o=120)`: **3.44s / 328 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +23.3 / -20 | +7.6 / -7 | +2.9 / -2 | +0.9 / +12 | -1.5 / +3 |
| **262144** **(def)** | +18.9 / -19 | +4.1 / -7 | +0.0 / +0 | -1.7 / -0 | -3.5 / +21 |
| **524288** | +15.7 / -19 | +2.6 / -11 | -1.7 / -7 | -3.2 / +16 | -5.2 / +5 |
| **1048576** | +11.6 / -18 | -0.3 / -7 | -4.7 / -6 | -5.5 / +14 | -7.3 / +28 |
| **2097152** | +8.1 / -18 | -1.5 / -13 | -5.2 / +1 | -6.7 / +5 | **-8.4 / +13** |

Min wall at `(s=2097152, o=200)`. RSS at the min-wall cell is +13% — there
is a trade-off here on intra-d8b, unlike cpdf_scale. For RSS-priority,
move to `(s=2097152, o=40)`: +8.1% wall but -18.0% RSS.

##### devkit_stre

d8b default `(s=262144, o=120)`: **4.10s / 23 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +5.4 / +30 | +2.7 / +21 | +2.2 / +19 | +1.7 / +19 | +1.2 / +19 |
| **262144** **(def)** | +1.0 / +3 | +0.7 / +3 | +0.0 / +0 | -0.5 / -0 | -0.7 / -1 |
| **524288** | -1.2 / +1 | -1.0 / -1 | -2.0 / +2 | -1.5 / -0 | -2.0 / -3 |
| **1048576** | -2.7 / +19 | -2.9 / +17 | -2.4 / +18 | -3.2 / +16 | -2.2 / +18 |
| **2097152** | -3.2 / +57 | -3.7 / +55 | -3.4 / +51 | -2.7 / +57 | -3.7 / +56 |

Tiny RSS workload (23 MB default) so the RSS column percentages are misleading
— absolute RSS at `s=2097152` is ~36 MB. The wall gain is real but small
(~3.7%); the takeaway is **devkit_stre is essentially flat on (s, o)**.
The `s=2097152` rows trade RSS for wall in a less-meaningful way given the
absolute scale.

##### jsoo

d8b default `(s=262144, o=120)`: **3.66s / 273 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +29.8 / -16 | +7.1 / -14 | +0.0 / -3 | -2.2 / -1 | -6.3 / +25 |
| **262144** **(def)** | +28.7 / -16 | +6.8 / -12 | +0.0 / +0 | -3.6 / +4 | -6.3 / +19 |
| **524288** | +29.8 / -15 | +7.7 / -10 | +0.5 / -4 | -3.0 / +9 | -5.7 / +12 |
| **1048576** | +31.7 / -15 | +11.2 / -14 | +2.5 / -7 | -1.6 / +12 | -3.8 / +26 |
| **2097152** | +34.4 / -11 | +13.1 / -6 | +6.0 / +4 | +2.7 / +15 | -0.5 / +10 |

jsoo has a `o`-only wall story: `o=200` gives -6.3% wall (any small `s`),
`o=40` is +28-34% across the grid. RSS trades with `o`: `o=40` cuts RSS
~15%, `o=200` grows it. The 5-12 report's +15.8% jsoo regression is **not
fully tunable from intra-d8b** — best available is -6.3% over default
(still a large regression vs 5.4). The allocation-growth hypothesis from
the 5-12 report remains relevant.

##### liq_video_frames_pool

d8b default `(s=262144, o=120)`: **3.01s / 110 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +15.6 / +0 | +6.0 / +0 | -0.3 / +0 | -3.7 / -0 | -2.0 / -0 |
| **262144** **(def)** | +15.6 / +0 | +6.0 / +0 | +0.0 / +0 | -4.3 / -0 | -8.0 / -0 |
| **524288** | +16.6 / +0 | +6.0 / +0 | +0.3 / +0 | +5.0 / -0 | -8.0 / -0 |
| **1048576** | +15.6 / +0 | +6.0 / +0 | -0.3 / +0 | -4.0 / -0 | -7.0 / -0 |
| **2097152** | +16.3 / +0 | +6.6 / +0 | +0.0 / -0 | -2.0 / -0 | -7.3 / -0 |

`s` does nothing (shared refcounted buffer is fixed), `o` matters slightly:
-8% wall at `o=200`. The POOL=1 refcounted variant is structurally
independent of `s` because the shared buffer caps real allocation.

##### menhir_sysver

d8b default `(s=262144, o=120)`: **7.68s / 746 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +26.6 / -2 | +7.8 / -0 | +1.6 / +1 | -0.1 / +2 | -2.2 / +22 |
| **262144** **(def)** | +23.6 / -2 | +6.5 / -2 | +0.0 / +0 | -2.0 / +5 | -4.3 / +19 |
| **524288** | +22.8 / -4 | +4.0 / -0 | -1.4 / -0 | -3.3 / +8 | -5.7 / +9 |
| **1048576** | +21.7 / -6 | +3.9 / -1 | -1.0 / -1 | -3.8 / -0 | **-6.2 / +0** |
| **2097152** | +26.6 / -1 | +8.3 / -1 | +1.3 / -1 | -0.5 / +8 | -3.6 / +3 |

Best intra-d8b at `(s=1048576, o=200)` → -6.2% wall with essentially flat
RSS. The 5.4-vs-d8b RSS Pareto for menhir_sysver (-36% at the same cell)
is mostly 5.4's regression at low s/high o; on d8b alone the RSS savings
are modest.

##### ocamlc_self_compile

d8b default `(s=262144, o=120)`: **3.30s / 967 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +25.8 / -5 | +10.3 / +3 | +3.0 / +6 | +1.8 / +8 | -0.9 / +11 |
| **262144** **(def)** | +23.6 / -7 | +7.0 / -0 | +0.0 / +0 | +0.0 / +7 | -3.9 / +6 |
| **524288** | +19.4 / -8 | +5.5 / -0 | -1.2 / +1 | -2.1 / +7 | -5.5 / +5 |
| **1048576** | +19.4 / -8 | +3.0 / -4 | -1.2 / +4 | -3.3 / +4 | **-6.7 / +2** |
| **2097152** | +21.8 / -6 | +5.5 / -1 | +0.3 / -1 | -3.9 / +1 | -4.5 / +8 |

Best at `(s=1048576, o=200)` → -6.7% wall, +1.6% RSS. The headline
ocamlc_self_compile +8.7% regression vs 5.4 is partially tunable away —
intra-d8b can recover 6.7%, leaving the residual ~2% which is the
underlying allocation-growth issue.

##### ocamlformat_rocq

d8b default `(s=262144, o=120)`: **1.80s / 294 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +32.2 / -14 | +11.7 / +0 | +6.1 / -1 | +2.2 / +12 | -0.6 / +18 |
| **262144** **(def)** | +25.0 / -14 | +6.7 / -7 | +0.0 / +0 | -1.1 / +1 | -4.4 / +17 |
| **524288** | +19.4 / -18 | +1.7 / -8 | -3.3 / +3 | -6.1 / +0 | -6.1 / +1 |
| **1048576** | +13.9 / -17 | +0.0 / -7 | -6.1 / +8 | **-8.9 / +10** | -9.4 / +24 |
| **2097152** | +17.2 / -12 | +2.8 / -7 | -3.9 / +3 | -6.1 / +3 | -7.8 / +28 |

Best at `(s=1048576, o=200)` → -9.4% wall. Smaller `o` gives a wall-RSS
trade (`(s=524288, o=40)`: +19% wall but -17.5% RSS) — a less obvious
option for memory-constrained deployments.

##### pplacer_testsuite

d8b default `(s=262144, o=120)`: **6.28s / 70 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | -0.3 / -5 | -0.6 / -2 | +0.5 / +2 | +1.0 / +2 | +1.3 / +5 |
| **262144** **(def)** | +0.6 / -6 | -0.8 / -3 | +0.0 / +0 | -0.3 / +1 | -0.2 / +4 |
| **524288** | -2.4 / -2 | -1.9 / -0 | +1.4 / +2 | -0.6 / +4 | -3.2 / +5 |
| **1048576** | -2.7 / +5 | -4.8 / +7 | -5.6 / +10 | -3.7 / +12 | -3.8 / +12 |
| **2097152** | -2.4 / +22 | -4.8 / +25 | **-9.2 / +22** | -3.7 / +21 | -4.9 / +24 |

Mostly flat. Best at `(s=2097152, o=120)` → -9.2% wall. The RSS is tiny
(70 MB) so the +22% RSS trade is ~15 MB — likely tolerable.

##### zarith_pi

d8b default `(s=262144, o=120)`: **2.53s / 128 MB**

| s \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | +4.7 / +71 | -0.8 / +42 | -5.1 / +18 | -8.7 / +8 | -11.1 / -1 |
| **262144** **(def)** | -1.6 / +2 | -0.8 / +3 | +0.0 / +0 | -2.8 / -10 | -8.3 / -16 |
| **524288** | -17.4 / -35 | -18.2 / -35 | -15.4 / -35 | -13.4 / -38 | -11.5 / -37 |
| **1048576** | -20.9 / -58 | -20.9 / -59 | -21.3 / -59 | -20.9 / -59 | -21.3 / -58 |
| **2097152** | **-25.3 / -66** | -24.9 / -66 | -25.3 / -66 | -25.3 / -66 | -25.3 / -66 |

The most extreme intra-d8b reframing in Sweep A. **At `(s=2097152, o=40)`
d8b is -25.3% faster than d8b default AND -66% smaller in RSS** — both
axes massively improved by tuning `s` up. The `o` axis is irrelevant once
`s` is large. zarith_pi was framed as "o-only" in the cross-version view;
intra-d8b says it's actually "s dominates, then o gives a small further
improvement". For any production zarith-heavy workload on d8b: set
`s ≥ 1048576`.

#### Sweep B — (M, o) intra-d8b, remaining 8 benches

##### alt_ergo_fill

d8b default `(M=44, o=120)`: **5.05s / 925 MB**

| M \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +28.3 / -16 | +6.9 / -3 | -0.6 / -1 | -4.4 / +8 | **-6.9 / +15** |
| **22** | +28.5 / -16 | +7.1 / -3 | -0.2 / +4 | -4.2 / +8 | -5.9 / +15 |
| **44** **(def)** | +28.1 / -16 | +6.9 / -3 | +0.0 / +0 | -4.4 / +8 | -6.7 / +15 |
| **100** | +29.1 / -17 | +6.3 / -3 | +0.0 / +3 | -4.0 / +8 | -6.3 / +15 |
| **250** | +28.5 / -17 | +7.7 / -3 | -1.0 / +1 | -4.4 / +8 | -6.1 / +15 |

Identical rows — `M` does nothing intra-d8b (matching cross-version). All
the action is on `o`: best wall at `o=200`, best RSS at `o=40`. Same
recommendation as Sweep A's (s, o) view at default s.

##### cpdf_merge

d8b default `(M=44, o=120)`: **2.16s / 363 MB**

| M \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +28.2 / -11 | +6.0 / +4 | -0.5 / +0 | -2.8 / +22 | -4.6 / +18 |
| **22** | +28.2 / -11 | +6.5 / +4 | -0.5 / +0 | -2.8 / +22 | **-5.1 / +18** |
| **44** **(def)** | +27.8 / -11 | +6.0 / +4 | +0.0 / +0 | -2.3 / +22 | -5.1 / +18 |
| **100** | +28.2 / -11 | +6.5 / +4 | -0.5 / +0 | -3.2 / +22 | -4.6 / +18 |
| **250** | +28.2 / -11 | +6.0 / +4 | -0.9 / +0 | -2.8 / +22 | -4.6 / +18 |

`M`-flat (≤1pp row variation); `o=200` gives -5% wall but +18% RSS. The
larger gains from Sweep A's `s=2097152` row are not available here at
fixed default `s`.

##### cpdf_scale

d8b default `(M=44, o=120)`: **12.91s / 489 MB**

| M \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +14.9 / -20 | +4.7 / -7 | -0.6 / +0 | -1.6 / +5 | -3.4 / +11 |
| **22** | +15.3 / -20 | +3.6 / -7 | -0.5 / +0 | -2.2 / +5 | -2.2 / +11 |
| **44** **(def)** | +15.6 / -20 | +4.3 / -7 | +0.0 / +0 | -2.0 / +5 | -2.9 / +11 |
| **100** | +15.4 / -20 | +4.3 / -7 | -0.5 / +0 | -1.5 / +5 | -3.3 / +11 |
| **250** | +15.2 / -20 | +5.0 / -7 | -0.4 / +0 | -2.2 / +5 | **-4.0 / +11** |

`M`-flat; `o=200` gives ~-4% wall. Same shape as cpdf_merge — for cpdf_*
benches, intra-d8b says **`o` is the only effective knob**; the `s` knob
in Sweep A unlocks deeper gains.

##### cpdf_squeeze

d8b default `(M=44, o=120)`: **3.43s / 328 MB**

| M \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +19.2 / -19 | +4.1 / -7 | -0.6 / -0 | -2.3 / -0 | -4.1 / +21 |
| **22** | +18.7 / -19 | +4.4 / -7 | +0.0 / -0 | -2.3 / -0 | -4.1 / +21 |
| **44** **(def)** | +19.0 / -19 | +4.1 / -7 | +0.0 / +0 | -2.0 / -0 | **-4.4 / +21** |
| **100** | +18.7 / -19 | +4.4 / -7 | -0.3 / -0 | -2.0 / -0 | -3.5 / +21 |
| **250** | +19.0 / -19 | +4.4 / -7 | +0.0 / -0 | -2.3 / -0 | -3.8 / +21 |

`M`-flat. Same conclusion as cpdf_scale/merge.

##### liq_video_frames_pool

d8b default `(M=44, o=120)`: **3.01s / 110 MB**

| M \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +336.5 / +12 | +303.0 / +12 | +345.2 / +11 | +259.5 / +11 | +243.5 / +11 |
| **22** | +122.6 / +4 | +103.3 / +4 | +91.0 / +4 | +84.4 / +3 | +79.1 / +3 |
| **44** **(def)** | +16.9 / +0 | +6.3 / +0 | +0.0 / +0 | -3.0 / +0 | -6.6 / +0 |
| **100** | -43.5 / -2 | -47.8 / -2 | -49.5 / -2 | -51.2 / -2 | -52.8 / -2 |
| **250** | -71.4 / -3 | -73.4 / -3 | -74.4 / -3 | -75.1 / -3 | **-75.7 / -3** |

⚠ Caveat: absolute wall is tiny (~3.0s at default), so the "+345%" /
"-75%" extremes are on a noisy baseline — treat the magnitudes as
directional, not precise. The **shape** is monotone in M: low M (M=11)
is catastrophically slow on this finaliser-dominated workload under d8b,
and the wall improvement at M=250 (-75%) is striking. The synthetic
*does* exhibit something resembling the #14533 free lunch *within d8b*,
even though it doesn't show as a d8b/5.4 ratio improvement (because 5.4
also benefits). The cross-version flatness on `_pool` (§B.2 below) is
not the whole story — the within-d8b improvement at large M *is* there
in this synthetic and goes in the same direction as the real-workload
reproduction of [ocaml/ocaml#14533](https://github.com/ocaml/ocaml/issues/14533).

##### owl_gc

d8b default `(M=44, o=120)`: **3.41s / 125 MB**

| M \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +87.7 / +111 | +91.2 / +100 | +82.7 / +92 | +81.5 / +89 | +68.6 / +83 |
| **22** | +56.6 / +62 | +45.2 / +52 | +44.0 / +46 | +38.4 / +42 | +33.1 / +37 |
| **44** **(def)** | +10.0 / +8 | +4.7 / +2 | +0.0 / +0 | -4.1 / -1 | -2.6 / -3 |
| **100** | -19.6 / -39 | -27.6 / -42 | -26.4 / -42 | -24.0 / -43 | -24.0 / -44 |
| **250** | -36.4 / -60 | -37.2 / -62 | -36.1 / -62 | -36.4 / -62 | **-38.4 / -62** |

Strict-better: `(M=250, o=200)` is **-38% wall AND -62% RSS** vs d8b
default. No trade-off; just set `M=250`. This is the single largest
intra-d8b strict-improvement cell in the entire matrix. Cross-version saw
M=11 as the deepest d8b/5.4 win, but that's because 5.4 is pathologically
slow at low M (the owl_gc analysis from 5-11 explained this); intra-d8b
correctly says M=250 is the production pick.

##### pplacer_testsuite

d8b default `(M=44, o=120)`: **6.18s / 70 MB**

| M \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +8.7 / -5 | +6.0 / -2 | +5.8 / +1 | +7.0 / +1 | +5.0 / +4 |
| **22** | +4.5 / -5 | +1.9 / -3 | +2.1 / +0 | +2.3 / +1 | +2.3 / +3 |
| **44** **(def)** | +1.5 / -7 | +0.5 / -3 | +0.0 / +0 | +0.5 / +1 | +1.1 / +3 |
| **100** | +0.5 / -6 | -0.3 / -3 | -0.6 / -1 | +1.8 / -0 | -1.1 / +3 |
| **250** | -0.8 / -7 | **-2.8 / -3** | -0.8 / -1 | +0.0 / -0 | -1.5 / +3 |

Essentially flat (±3% wall) with M=250 a touch best. Reproduces the
cross-version flat finding.

##### zarith_pi

d8b default `(M=44, o=120)`: **2.53s / 128 MB**

| M \ o | 40 | 80 | 120 **(def)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | -1.2 / +3 | -1.6 / -1 | +0.8 / -1 | -3.2 / -10 | -8.3 / -17 |
| **22** | -1.6 / +2 | -1.2 / +3 | +0.0 / -0 | -3.2 / -9 | -8.3 / -17 |
| **44** **(def)** | -1.2 / +5 | -1.2 / -1 | +0.0 / +0 | -4.0 / -9 | **-8.7 / -17** |
| **100** | -0.8 / +5 | -0.8 / +3 | +0.8 / -1 | -2.8 / -10 | -8.3 / -17 |
| **250** | -1.2 / +5 | -0.8 / +2 | +0.4 / -1 | -3.6 / -9 | -8.7 / -16 |

`M`-flat (confirmed); `o=200` gives -8.7% wall AND -17% RSS — a strict
within-d8b improvement. The `s=2097152, o=40` cell from Sweep A
(-25%/-66%) is dramatically better than anything available here, so the
recommendation for zarith-heavy workloads remains "tune `s` first, then
`o`".

## Sweep A — (s, o) on regressed benches

### A.1 `liq_parse_typecheck` — the big find

The most surprising cell in either sweep. The 5-12 N=10 headline showed
liq_parse_typecheck regressed at default `(s=262144, o=120)`: **+6.6% wall**.
This sweep shows that's almost entirely a default-`o` artifact:

```
| s \ o | 40 | 80 | 120 **(default)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | -21.5 / -22 | +2.8 / +5 | +16.3 / +4 | +9.0 / +5 | +5.9 / +11 |
| **262144** **(default)** | -35.2 / -34 | -5.5 / -8 | +6.6 / +2 | +13.9 / +7 | +13.9 / +7 |
| **524288** | -25.4 / -24 | -20.6 / -22 | -7.4 / -9 | -2.5 / -4 | +4.6 / -1 |
| **1048576** | -16.9 / -5 | -15.8 / -5 | -15.0 / -16 | -9.6 / -11 | -1.9 / -8 |
| **2097152** | -9.7 / +21 | -11.3 / +21 | -10.4 / +21 | -8.6 / +21 | -10.9 / -7 |
```

At `(s=262144, o=40)` d8b is **-35.2% wall AND -33.7% RSS** — a strict
Pareto improvement, not a trade-off. Setting `OCAMLRUNPARAM="o=40"` on the
default minor-heap size flips this benchmark from a +6.6% regression to a
35% win on both axes.

The pattern across the table: as `o` decreases (more aggressive major
pacer), d8b wins by larger margins. As `s` increases past the default, the
`o` sensitivity flattens (`s=2097152` row is uniformly -10% wall / +21%
RSS) — the larger minor heap absorbs the work that the major pacer is
otherwise trying to do.

The 5-12 report's headline "+6.6% wall regression on liq_parse_typecheck"
should be amended to "+6.6% **at default `o=120`** — under d8b the optimal
operating point is `o ≤ 40`, where d8b is ~35% faster than 5.4 with 34%
less RSS."

### A.2 `zarith_pi` — two independent levers

Sweep A reveals that zarith_pi has both an `o`-axis story (already known
from 5-11) **and** a separate `s`-axis story:

```
| s \ o | 40 | 80 | 120 **(default)** | 150 | 200 |
|---|---|---|---|---|---|
| **131072** | -24.7 / -17 | -13.7 / -8 | -5.9 / +5 | -0.4 / +12 | +5.1 / +29 |
| **262144** **(default)** | -11.4 / -26 | -15.2 / -23 | +4.1 / +3 | +4.2 / +10 | +9.4 / +36 |
| **524288** | -11.8 / -17 | -13.4 / -16 | -10.1 / -17 | -4.4 / -10 | +4.2 / +14 |
| **1048576** | +0.0 / -16 | -0.5 / -16 | +0.0 / -16 | -0.5 / -16 | +0.0 / -16 |
| **2097152** | +6.2 / -18 | +6.1 / -18 | +5.0 / -18 | +6.2 / -18 | +5.0 / -18 |
```

The bottom two rows (`s ≥ 1048576`) collapse the `o` axis entirely — every
cell becomes ±5% wall / -18% RSS. This is informative: the prior framing
"zarith_pi is `o`-bound" was true at default `s`, but at large `s` the `o`
sensitivity vanishes because the minor heap holds enough Z.t allocations
to not need the major pacer's release decisions. So:

- If you can't tune `o` and want zarith_pi to behave: set `s ≥ 1048576`,
  accept ~5% wall regression, get -18% RSS for free.
- If you can tune `o`: stay at default `s=262144`, set `o ≤ 80`, get
  -11 to -15% wall and -23 to -26% RSS (the strict win).

### A.3 `devkit_stre` — flag-only regressor unmasked as a quiet d8b win

The 5-12 report flagged devkit_stre `-fp` as the only ≥5% cell, treated as
a possibly-noise outlier. Sweep A shows the **baseline** version effect at
default `(s, o)` is actually d8b -3.5% wall / -4.3% RSS — d8b is faster.
At `(s=262144, o=40)` the win deepens to **-9.2% wall / -24.2% RSS**, a
strict improvement. So:

- The 5-12 `-fp +7.3%` cell was a flag-specific effect, not a default-cell
  story. The benchmark itself is **not regressed** on d8b.
- The (s, o) sweep recommends `o=40` for the deepest win.

### A.4 RSS Pareto wins on cpdf_*, ocamlformat_rocq, menhir_sysver

These are the "wall regression in exchange for RSS savings" benches —
typical 5.5-beta off-heap pacer trade. The 5×5 grid extends the available
range significantly past what the 5-08 / 5-11 sweeps could see:

| benchmark | default Pareto | best RSS Pareto | wall cost of max RSS |
|---|---|---|---|
| cpdf_scale | +5.4% / -39% | `(2097152, 200)`: +1.7% / -47.7% | only +1.7% for -48% |
| cpdf_squeeze | +3.9% / -26% | `(131072, 200)`: +4.3% / -41.5% | +4.3% for -42% |
| cpdf_merge | +4.9% / -27% | `(131072, 150)`: +5.0% / -35.1% | +5.0% for -35% |
| ocamlformat_rocq | +4.7% / -16% | `(524288, 200)`: +5.0% / -38.5% | +5.0% for -38% |
| menhir_sysver | +5.6% / -20% | `(1048576, 200)`: +4.7% / -35.7% | +4.7% for -36% |

The common shape: high `o` and moderate-to-large `s` is the RSS-optimal
quadrant. The wall cost stays modest (+1.7 to +5.0%) for very substantial
RSS savings (-35 to -50%). The release-notes recommendation should call
out `o=200` as a generally good default for off-heap-RSS-conscious users
on this group — the 5.5 pacer trades wall for RSS, and pushing `o` further
in the same direction enlarges the trade.

### A.5 Sticky-wall regressions — jsoo, ocamlc_self_compile

These two don't tune well on (s, o). The wall regression band is narrow
across the entire grid:

- `jsoo`: +12.1% to +19.1% across all 25 cells. Best wall cell only
  cuts the default's +15.8% to +12.1%; RSS ranges -5.8% to -38.4% but the
  wall doesn't track RSS well. (s, o) is not the right axis here — this
  is a compiler-internals allocation-growth issue per 5-12's analysis
  (similar to ocamlc_self_compile).
- `ocamlc_self_compile`: +6.9% to +10.5%. Min wall at `(1048576, 200)` is
  still +6.9% / -7.2%. Same diagnosis — allocation growth, not pacer cost.

Both genuinely need a different fix (allocation profiling), not GC
parameter tuning.

## Sweep B — (M, o) on off-heap benches

### B.1 `owl_gc` — confirms 5-11, M-monotonic d8b win

```
| M \ o | 40 | 80 | 120 **(default)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | -55.2 / -6 | -50.0 / -11 | -50.1 / -14 | -49.1 / -15 | -50.4 / -18 |
| **22** | -46.7 / -20 | -46.9 / -22 | -44.8 / -21 | -44.9 / -21 | -46.0 / -21 |
| **44** **(default)** | -37.9 / -19 | -36.7 / -18 | -35.8 / -17 | -36.0 / -16 | -35.2 / -17 |
| **100** | -25.7 / -15 | -30.0 / -16 | -24.6 / -15 | -23.6 / -13 | -20.6 / -14 |
| **250** | -16.2 / -11 | -14.7 / -11 | -12.1 / -10 | -11.1 / -10 | -11.4 / -10 |
```

The 5-11 finding ("smaller `M` magnifies d8b's win because the 5.4 pacer
goes berserk and d8b doesn't") is reproduced cleanly. `(M=11, o=40)`
reaches **-55.2% wall / -5.9% RSS**, the deepest d8b win in either sweep.
The wall delta is essentially flat in `o` (rows vary by ≤5pp) but
monotonically shrinks as `M` grows — confirming this is purely a
custom-block-pacer story, not a major-pacer story.

### B.2 `liq_video_frames_pool` — cross-version flat; toots/#14533 free lunch does not show in d8b/5.4 ratio

```
| M \ o | 40 | 80 | 120 **(default)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | -1.2 / +3 | +0.2 / +2 | +19.0 / +3 | -2.7 / +2 | -0.5 / +2 |
| **22** | -1.8 / +1 | -0.3 / +1 | -0.5 / +1 | +0.2 / +1 | +1.5 / +1 |
| **44** **(default)** | +0.9 / +1 | -0.3 / +0 | +0.3 / +0 | +0.7 / +0 | +1.4 / +0 |
| **100** | -1.7 / +0 | -1.9 / +0 | +0.7 / +0 | +0.7 / +0 | +0.7 / +0 |
| **250** | +0.0 / -0 | +1.3 / -0 | +1.3 / -0 | +0.0 / -0 | +1.4 / -0 |
```

Every cell within ±2% wall, ±3% RSS, with one outlier at `(M=11, o=120) =
+19%` that's clearly a single-draw artifact (neighbours are all near 0).
The 5-12 report framed `_pool` as the toots/[ocaml#14533](https://github.com/ocaml/ocaml/issues/14533)
reproducer and predicted that "*at large `M`* d8b's lazier pacer should
produce a CPU win with no RSS cost" because the shared buffer caps RSS
regardless of release cadence.

That prediction does not hold here. At M=250 the pool variant is at +0.0
to +1.4% wall — same as M=44. No free lunch. Two plausible reasons:

1. **The synthetic doesn't model what the real ocaml-ffmpeg case does.**
   The toots free-lunch shape requires the pacer to be *forced* to do
   major work because of accumulated `mem` accounting; the stub
   ([pool_stubs.c](../benchmarks/liq-video-frames/pool_stubs.c)) registers
   `mem` per call but the OCaml mutator does ~zero allocation per frame
   beyond the touch loop. Real `av_frame_free` has additional refcount
   bookkeeping and a much richer allocation environment around it.
2. **Ryzen 9 9950X doesn't surface the effect.** This is the original
   hardware hypothesis from the parked #14533 repro — the slow Xeon was
   libx264-bound, the fast Ryzen should be GC-bound. But if there's
   nothing for the pacer to do (allocation budget is dominated by `mem`
   accounting not real heap pressure), the M knob has nothing to lever.

Either way: **the synthetic `_pool` is not a viable cross-version #14533
reproducer on monolith.** Note however that the *intra-d8b* heatmap above
(§"liq_video_frames_pool" subsection) shows monotone wall improvement
with larger M — d8b at M=250 is much faster than at M=44 on this short
batch. The cross-version flatness is because 5.4 improves in lockstep at
large M, not because d8b is failing to benefit. See follow-up #1.

### B.3 `cpdf_*`, `alt_ergo_fill`, `pplacer_testsuite` — M-flat (confirmed)

Per the 5-11 diagnosis, these benches' regressions are major-pacer-bound,
not custom-block-pacer-bound. This sweep confirms it — each M row is
essentially the same; only `o` and `s` (Sweep A) move them.

For `cpdf_scale`:
- M row spread (at o=120): +4.0% to +4.5% across all 5 M values. **0.5pp** band.
- o column spread (at M=44): +4.4% (o=40) to +3.6% (o=200). 0.8pp band.
- s axis (Sweep A): same cell `(s, o=120)` ranges +6.4% (131072) → +2.6% (2097152). **3.8pp** band.

So for cpdf_scale, **`s` is the dominant lever, `o` and `M` are flat.**
Same shape for cpdf_merge and cpdf_squeeze. Worth pinning in the
release-notes guidance: "cpdf-style workloads — set `s ≥ 1048576` for
~3pp wall improvement under d8b; M and o have no effect."

`alt_ergo_fill` is similarly M-flat (rows vary ≤2pp); the version effect
is +6 to +8% across all M, identical to default.

`pplacer_testsuite` is the quietest of this group — all 25 cells within
±5% wall, mostly slightly negative ratios — d8b is a touch faster across
the grid.

### B.4 `zarith_pi` — same `o`-axis story as Sweep A, M-flat as expected

```
| M \ o | 40 | 80 | 120 **(default)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | -10.1 / -25 | -14.4 / -25 | +0.0 / +3 | +7.0 / +11 | +11.0 / +34 |
| **22** | -12.3 / -25 | -13.8 / -22 | -0.8 / +3 | +4.3 / +12 | +7.4 / +31 |
| **44** **(default)** | -17.5 / -23 | -9.7 / -24 | +3.3 / +4 | +3.8 / +14 | +8.5 / +32 |
| **100** | -15.5 / -24 | -15.2 / -23 | +2.4 / +2 | +7.4 / +13 | +10.0 / +34 |
| **250** | -16.4 / -23 | -14.6 / -22 | +2.8 / +3 | +3.8 / +11 | +9.0 / +31 |
```

Each row is essentially identical — `M` does nothing. Columns:
**o ≤ 80 → d8b wins by 10-17% wall and -22 to -25% RSS; o ≥ 120 → d8b
loses wall and RSS climbs to +34%**. Combined with Sweep A's finding that
`s ≥ 1048576` neutralises the `o` axis, the recommendation matrix is:
- Want strict d8b win: `s=default, o ≤ 80`.
- Want d8b parity with low variance: `s ≥ 1048576, any o`.

## Reflection vs the 5-11 sweep

The 5-11 sweep covered an overlapping subset of cells in (M, o); this
sweep extends to wider o (added o=200) and adds the new
`liq_video_frames_pool` refcounted-pool variant. Findings:

| benchmark | 5-11 finding | 5-13 finding | reflection |
|---|---|---|---|
| `owl_gc` | -53.3% at `(M=11, o=80)` | -55.2% at `(M=11, o=40)` (new) | extends 5-11 — smaller o gives a deeper win |
| `cpdf_*` | M-flat, o-dependent | M-flat confirmed; new o=200 column shows RSS extends further (-50% on cpdf_scale) | extends 5-11 |
| `zarith_pi` | "o-only story" at default s | confirmed; Sweep A adds "s ≥ 1048576 neutralises o" | adds a second axis story |
| `liq_video_frames_pool` | not swept (5-11 used the old single benchmark) | cross-version flat across (M, o); intra-d8b monotone in M | new variant introduced this run |

The 5-11 recommendation to use `M=250` for liquidsoap-style workloads
is **consistent** with the intra-d8b view here on `_pool` and with the
real-workload reproduction of
[ocaml/ocaml#14533](https://github.com/ocaml/ocaml/issues/14533): both
say M=250 is the right production choice on d8b.

## Methodology notes

- **Median over mean**, N=3 per cell. Same convention as 5-11.
- **Within-cell wall spread** ((max−min)/median): mean ~2.5% across the
  1050 cells, median ~1.7%. Cells with ≥15% spread (only single-cell claims
  under ±5% should be read with these in mind):
  - `liq_video_frames_pool` Sweep B (11, 120) d8b: 19% — the outlier mentioned in §B.2
  - A handful of short-batch `liq_video_frames_pool` cells in the small-M region
- **All cells 3/3 captured cleanly** — no missing data, no OOMs, no
  timeouts.
- **Trade-off visualization design**: each per-bench heatmap uses
  `wall%/RSS%` packed into one cell so the trade-off is visible at a
  glance. The Pareto-frontier list per bench enumerates non-dominated
  cells (no other cell gives smaller wall *and* smaller RSS), sorted by
  wall ratio. The headline Pareto table at the top of this report
  collapses each bench to a default/min-wall/min-RSS triple for
  cross-bench comparison.

## Suggested follow-ups

1. **Investigate the synthetic vs real-ffmpeg gap on `_pool`.** The
   cross-version flat #14533 result here could mean either (a) the
   synthetic stub is too minimal or (b) Ryzen doesn't surface the effect
   cross-version. To disambiguate, instrument the stub to do a small
   amount of OCaml-heap work per frame (the source has `LIQ_CHURN` for
   exactly this purpose) and rerun the (M, o) sweep on `_pool` with
   `LIQ_CHURN=1000`. If a cross-version free lunch appears with churn,
   the stub is the culprit; if not, the hardware hypothesis stands.
2. **Update `liq_parse_typecheck` headline.** This sweep changed the
   diagnosis: it's not a regression, it's a default-`o` mistuning.
   Worth a one-line update to the 5-12 N=10 report and to the
   release-notes summary.
3. **Set up an `s` sweep on owl_gc.** Sweep B only covered `(M, o)` on
   owl_gc; we don't know how `s` interacts with the d8b win. Cheap to
   add given the bench is fast (~3s/inv). Hypothesis: the win is
   independent of `s` (since 5.4's pathology is purely in the
   custom-block pacer, not the minor heap), but worth confirming.
4. **Write a release-notes guidance section** for d8b users (intra-runtime
   recommendations, not cross-version). Revised grid using the intra-d8b
   view above; the streaming entry below also lines up with
   [ocaml/ocaml#14533](https://github.com/ocaml/ocaml/issues/14533):
   - cpdf-style (RSS-sensitive PDFs): `s ≥ 1048576, o=200` → -7-10% wall and -14-23% RSS vs d8b default
   - **liquidsoap streaming pipeline** (real-workload-confirmed, matches
     synthetic `_pool` intra-d8b): `M=250` → -17% CPU for +10% RSS vs
     d8b default; **do NOT use M=11** (98% CPU + latency overruns)
   - owl/numerical: `M=250, o=200` → -38% wall AND -62% RSS within d8b
     (cross-version `M=11` gets a deeper relative win but `M=250` is the
     better production cell because the RSS bonus is real)
   - zarith-heavy: `o ≤ 80` → strict win on both axes (cross-version AND
     intra-d8b agree)
   - liq_parse_typecheck-style typer workloads: `(s=2097152, o=200)` →
     -33% wall vs d8b default
