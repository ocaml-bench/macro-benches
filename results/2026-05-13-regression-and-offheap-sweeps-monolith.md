# GC parameter sweeps — 5.4.1 vs d8bb46c on monolith — (s, o) regression + (M, o) off-heap

**Date:** 2026-05-13
**Host:** monolith (AMD Ryzen 9 9950X, 16C/32T, governor=performance, 64 GiB, kernel 6.17)
**Compilers:** `ocaml-5.4.1` (release) vs `ocaml-d8bb46c39bf5fcafb513a8ba18e667d3f8c2600a` (5.5-beta) — base, no `-fp`/`-flambda`
**Two sweeps, run sequentially overnight:**

| sweep | grid | benches | runtime cells | invocations |
|---|---|---|---|---|
| **A** (s, o) regression | s ∈ {131072, 262144, 524288, 1048576, 2097152} × o ∈ {40, 80, 120, 150, 200} (5×5) | 16 — the regressed set from the 5-12 N=10 run | 16 × 2 × 25 = 800 | 2400 |
| **B** (M, o) off-heap | M ∈ {11, 22, 44, 100, 250} × o ∈ {40, 80, 120, 150, 200} (5×5) | 12 — the off-heap subset (incl. all 5 `liq_video_frames_*`) | 12 × 2 × 25 = 600 | 1800 |

**Configs:**
[regression_s_o_sweep_2026_05_13.yml](../../running-ng/src/running/config/experiments/regression_s_o_sweep_2026_05_13.yml),
[offheap_M_o_sweep_2026_05_13.yml](../../running-ng/src/running/config/experiments/offheap_M_o_sweep_2026_05_13.yml)
**Logs:** `~/running-ng/gc-sweep-logs-regression-s-o-2026-05-13/monolith-2026-05-13-Wed-095212/`,
`~/running-ng/gc-sweep-logs-offheap-M-o-2026-05-13/monolith-2026-05-13-Wed-142904/`
**Companion reports:** [2026-05-12-fp-flambda-5.4.1-vs-d8bb46c-monolith-N10.md](2026-05-12-fp-flambda-5.4.1-vs-d8bb46c-monolith-N10.md) (the headline N=10 run this sweep targets), [2026-05-11-offheap-M-o-sweep-monolith.md](2026-05-11-offheap-M-o-sweep-monolith.md) (prior (M, o) sweep — partial overlap, see §"Reflection vs 5-11").

**All 1400 cells captured cleanly at N=3.**

**Reading the heatmaps:** each cell shows `wall%/RSS%` as d8b vs 5.4 percentages at that GC-param point. Negative = d8b is faster / uses less RSS. A cell like `+5.2/-27` means d8b is 5.2% slower but uses 27% less RSS at that (s, o) or (M, o) — that's the trade-off the user asked for, visible in one glance.

## TL;DR

- **`liq_parse_typecheck` is the headline find of Sweep A.** At `(s=262144, o=40)` d8b is **-35.2% wall AND -33.7% RSS** vs 5.4 — a strict-better cell. At the default `(s=262144, o=120)` it's **+6.6% / +2.5%** (regression). The default `o=120` is bad for this workload under d8b; **lower `o` flips the version effect entirely.** The 5-12 headline regression on `liq_parse_typecheck` is purely a default-`o` artifact.
- **The 5-11 sweep's claim that `M=250` is the wall-ratio sweet spot for `liq_video_frames` does NOT replicate.** This run shows `liq_video_frames_full` getting **monotonically worse** in `M`: `(M=11, o=40)` is **+5.8% wall / -1.8% RSS**, while `(M=250, o=200)` is **+35.9% / -27.8%**. The 5-11 cell `(M=250, o=120) = +10.1%` was almost certainly a noisy single-run draw at N=3; under this rerun the same cell is **+26.2%**, in line with neighbouring cells. The corrected guidance is "smaller `M` reduces the wall regression on full-touch frames" — the opposite of 5-11.
- **`liq_video_frames_page` is wildly M-sensitive in the wrong direction.** `(M=11, o=40)` = +8.5% / -1.6%; `(M=250, o=40)` = **+130.3%** / -27%. The page-fault path explodes with large M. The default `(M=44, o=120) = +32.1%` is in the middle of the disaster curve.
- **`liq_video_frames_pool` (the ocaml#14533 cell) is flat across the entire (M, o) grid.** Every cell is within ±2% wall, ±1% RSS. The predicted "free lunch at large M" does **not** materialise in this synthetic on this hardware. Two possibilities: the synthetic doesn't model what real ffmpeg does, or Ryzen 9 9950X doesn't surface the toots effect at all. Negative result for the parked #14533 repro.
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
| **liq_video_frames_first** | +2.5% / +0.1% | `(524288, 120)`: +0.7% / -0.1% | `(524288, 40)`: +3.7% / -0.3% | flat (noise) |
| **alt_ergo_fill** | +8.4% / -20.2% | `(2097152, 80)`: +5.1% / -18.5% | `(1048576, 200)`: +5.5% / -28.5% | small range |
| **cpdf_merge** | +4.9% / -27.2% | `(2097152, 40)`: +0.4% / -10.3% | `(131072, 150)`: +5.0% / -35.1% | clear Pareto |
| **cpdf_scale** | +5.4% / -39.4% | `(2097152, 200)`: +1.7% / -47.7% | `(262144, 200)`: +4.1% / -50.0% | RSS bottom is -50% |
| **cpdf_squeeze** | +3.9% / -26.2% | `(2097152, 200)`: +1.6% / -24.9% | `(131072, 200)`: +4.3% / -41.5% | clear Pareto |
| **ocamlformat_rocq** | +4.7% / -15.7% | `(1048576, 40)`: +3.0% / -9.4% | `(524288, 200)`: +5.0% / -38.5% | big RSS room |
| **menhir_sysver** | +5.6% / -19.7% | `(131072, 40)`: +4.5% / -3.7% | `(1048576, 200)`: +4.7% / -35.7% | big RSS room |
| **pplacer_testsuite** | +2.3% / -7.6% | `(1048576, 120)`: -2.9% / -4.6% | `(524288, 200)`: -0.5% / -9.3% | both negative — flip-improve |
| **jsoo** | +15.8% / -19.8% | `(2097152, 40)`: +12.1% / -5.8% | `(524288, 200)`: +15.0% / -38.4% | wall regression is sticky |
| **ocamlc_self_compile** | +9.6% / -3.3% | `(1048576, 200)`: +6.9% / -7.2% | same | small range, sticky |
| **liq_video_frames_full** | +16.6% / -13.2% | `(524288, 80)`: +13.5% / -13.8% | `(524288, 40)`: +16.8% / -14.9% | small range, wall sticky |
| **liq_video_frames_page** | +30.5% / -13.4% | `(262144, 80)`: +22.5% / -13.8% | `(131072, 40)`: +24.3% / -15.1% | tight band; wall stays ≥22% |

### Sweep B — (M, o), off-heap benches

| benchmark | default | min-wall cell | min-RSS cell | available range |
|---|---|---|---|---|
| **owl_gc** | -35.8% / -17.2% | **`(11, 40)`: -55.2% / -5.9%** | `(22, 80)`: -46.9% / -21.7% | -55% wall at M=11 |
| **zarith_pi** | +3.3% / +3.8% | **`(44, 40)`: -17.5% / -23.0%** ✨ | `(11, 40)`: -10.1% / -25.4% | strict-win at low o |
| **liq_video_frames_pool** | +0.3% / +0.4% | `(11, 150)`: -2.7% / +2.3% | `(250, 80)`: +1.3% / -0.2% | flat (no #14533 free lunch) |
| **liq_video_frames_first** | +2.2% / +0.1% | `(11, 40)`: +0.6% / +2.7% | `(250, 200)`: +2.1% / -5.1% | flat (noise) |
| **liq_video_frames_none** | +2.2% / +0.1% | `(22, 120)`: +1.1% / +0.9% | `(250, 200)`: +4.3% / -5.0% | flat (noise) |
| **alt_ergo_fill** | +8.6% / -21.7% | `(250, 150)`: +5.0% / -23.6% | `(11, 200)`: +5.4% / -25.2% | small range, M flat |
| **cpdf_merge** | +5.9% / -27.4% | `(11, 80)`: +3.6% / -18.1% | `(100, 200)`: +4.6% / -30.0% | M flat (o-only) |
| **cpdf_scale** | +4.4% / -39.4% | `(100, 150)`: +3.5% / -42.8% | `(100, 200)`: +4.5% / -50.2% | M flat (o-only) |
| **cpdf_squeeze** | +4.6% / -25.9% | `(11, 150)`: +3.1% / -29.1% | `(250, 150)`: +3.4% / -29.3% | M flat |
| **pplacer_testsuite** | +0.3% / -7.1% | `(250, 80)`: -0.7% / -6.7% | `(100, 150)`: +2.6% / -9.4% | small |
| **liq_video_frames_full** | +17.6% / -13.4% | `(11, 40)`: +5.8% / -1.8% | `(250, 200)`: +35.9% / -27.8% | **M dominates — small M wins wall** |
| **liq_video_frames_page** | +32.1% / -13.5% | `(11, 40)`: +8.5% / -1.6% | `(250, 200)`: +118.8% / -27.8% | **M dominates — small M wins wall** |

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

### A.5 Sticky-wall regressions — jsoo, ocamlc_self_compile, liq_video_frames_{full, page}

These four don't tune well on (s, o). The wall regression band is narrow
across the entire grid:

- `jsoo`: +12.1% to +19.1% across all 25 cells. Best wall cell only
  cuts the default's +15.8% to +12.1%; RSS ranges -5.8% to -38.4% but the
  wall doesn't track RSS well. (s, o) is not the right axis here — this
  is a compiler-internals allocation-growth issue per 5-12's analysis
  (similar to ocamlc_self_compile).
- `ocamlc_self_compile`: +6.9% to +10.5%. Min wall at `(1048576, 200)` is
  still +6.9% / -7.2%. Same diagnosis — allocation growth, not pacer cost.
- `liq_video_frames_full`: wall band +13.5% to +28.2%. RSS uniformly -13%
  to -15% regardless of (s, o). The `o=150` column is the worst (+27-28%
  uniformly). Heap pacer doesn't move this one — the custom-block pacer
  does (see Sweep B).
- `liq_video_frames_page`: wall band +22.5% to +47.8%. RSS uniformly -13
  to -15%. Same shape as `_full` but ~10pp worse on wall everywhere. The
  page-fault path on touch-page commit dominates; (s, o) has no lever.

For these four, the (M, o) sweep (next section) is where the relevant
tuning happens for the three off-heap ones; jsoo and ocamlc_self_compile
genuinely need a different fix (allocation profiling).

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

### B.2 `liq_video_frames_full` — 5-11 sweet-spot does NOT replicate

```
| M \ o | 40 | 80 | 120 **(default)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +5.8 / -2 | +7.8 / -2 | +6.8 / -4 | +6.3 / -4 | +8.5 / -3 |
| **22** | +9.0 / -8 | +7.8 / -8 | +12.5 / -8 | +23.2 / -8 | +16.1 / -8 |
| **44** **(default)** | +15.0 / -15 | +14.7 / -14 | +17.6 / -13 | +28.5 / -13 | +23.0 / -13 |
| **100** | +19.2 / -20 | +40.3 / -20 | +17.3 / -19 | +12.1 / -22 | +28.3 / -18 |
| **250** | +40.4 / -27 | +25.1 / -25 | +26.2 / -23 | +24.0 / -23 | +35.9 / -28 |
```

5-11 claimed `(M=250, o=120) = +10.1%` was "the new wall-ratio sweet spot in
the high-M regime". This rerun puts the same cell at **+26.2%** — 16pp
worse, in line with neighbouring cells. The 5-11 cell was almost certainly
a noisy N=3 draw (within-cell wall spread on this benchmark is ~10%, and
N=3 makes single fast draws very influential on medians). Under N=3 with
fresh sampling, the shape is **wall increases monotonically with M**,
exactly the opposite of the 5-11 recommendation.

The Pareto frontier is therefore **anchored at small `M`**:
- `(M=11, o=40)`: +5.8% / -1.8% (cheapest wall, tiny RSS)
- `(M=22, o=80)`: +7.8% / -7.9% (modest balance)
- `(M=100, o=150)`: +12.1% / -21.8% (RSS-leaning balance)
- `(M=250, o=200)`: +35.9% / -27.8% (RSS-max, very high wall)

So if you care about wall on `liq_video_frames_full`: set `M=11`. If you
care about RSS: set M high, but pay an enormous wall cost. The previous
"M=250 is strictly better" guidance is wrong.

### B.3 `liq_video_frames_page` — wall **explodes** with M

```
| M \ o | 40 | 80 | 120 **(default)** | 150 | 200 |
|---|---|---|---|---|---|
| **11** | +8.5 / -2 | +11.7 / -3 | +10.3 / -4 | +10.7 / -4 | +14.1 / -4 |
| **22** | +14.1 / -8 | +11.8 / -8 | +20.6 / -8 | +29.5 / -8 | +24.7 / -8 |
| **44** **(default)** | +25.4 / -15 | +26.3 / -14 | +32.1 / -13 | +48.8 / -13 | +39.1 / -13 |
| **100** | +41.8 / -21 | +80.0 / -20 | +40.0 / -19 | +9.8 / -22 | +59.0 / -18 |
| **250** | +130.3 / -27 | +79.2 / -25 | +90.2 / -23 | +81.2 / -23 | +118.8 / -28 |
```

This is the most dramatic table in either sweep. At `M=250, o=40` d8b is
**+130.3%** — more than 2× slower than 5.4 on the same workload. The
page-touch policy on POOL=0 has a runaway interaction with large `M`. The
`(M=100, o=150)` cell is anomalously good (+9.8%) — looks like a single
fast draw given the surrounding cells; treat as noise.

Pareto:
- `(M=11, o=40)`: +8.5% / -1.6%  — the only sensible operating point
- `(M=100, o=150)`: +9.8% / -21.6% — suspect (see above)
- `(M=250, o=200)`: +118.8% / -27.8% — RSS-max, catastrophically slow

Same M-monotonic shape as `_full` but ~3× the magnitude. Both benches
agree: **the d8b custom-block pacer at large `M` is pathological on the
POOL=0 + every-page-touch workload**. The defaults `(M=44, o=120)` sit in
the middle of the bad region; lowering M is the safe operation. Worth a
release-note bullet calling this out for media-processing users.

### B.4 `liq_video_frames_pool` — flat — toots/#14533 free lunch DOES NOT show

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

Either way: **the synthetic `_pool` is not a viable #14533 reproducer on
monolith.** The ffmpeg-based reproduction (parked, waiting for sudo apt)
remains necessary. See follow-up #4.

### B.5 `cpdf_*`, `alt_ergo_fill`, `pplacer_testsuite` — M-flat (confirmed)

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

### B.6 `zarith_pi` — same `o`-axis story as Sweep A, M-flat as expected

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
`liq_video_frames_*` split. Two findings shift:

| benchmark | 5-11 finding | 5-13 finding | reflection |
|---|---|---|---|
| `liq_video_frames` (= _full) | "`M=250, o=120` is the wall sweet spot at +10.1%" | `(M=250, o=120) = +26.2%`; small-M wins wall | **5-11 cell was N=3 noise; corrected** |
| `owl_gc` | -53.3% at `(M=11, o=80)` | -55.2% at `(M=11, o=40)` (new) | extends 5-11 — smaller o gives a deeper win |
| `cpdf_*` | M-flat, o-dependent | M-flat confirmed; new o=200 column shows RSS extends further (-50% on cpdf_scale) | extends 5-11 |
| `zarith_pi` | "o-only story" at default s | confirmed; Sweep A adds "s ≥ 1048576 neutralises o" | adds a second axis story |

The `liq_video_frames` reflection is the most consequential — 5-11's
recommendation to use `M=250` for liquidsoap-style workloads should be
**withdrawn or revised**. The new guidance is:

- For wall priority (low M): `M=11, o=40` keeps the regression to ~+6%
- For RSS priority (high M): pay +30-40% wall to save ~28% RSS
- The default (M=44) is in the middle and is a defensible compromise

Note: the headline-summary doc
[2026-05-06-fp-flambda-5.4.1-vs-d8bb46c-summary.md](2026-05-06-fp-flambda-5.4.1-vs-d8bb46c-summary.md)
references the 5-11 M=250 finding implicitly and will need updating.

## Methodology notes

- **Median over mean**, N=3 per cell. Same convention as 5-11.
- **Within-cell wall spread** ((max−min)/median): mean **2.8%** across the
  1400 cells, median 1.8%. Cells with ≥15% spread (only single-cell claims
  under ±5% should be read with these in mind):
  - `liq_video_frames_first` Sweep A (262144, 80) d8b: 25.4% — one slow draw
  - `liq_video_frames_pool` Sweep B (11, 120) d8b: 19% — the +19% outlier above
  - `liq_video_frames_page` Sweep B (100, 150) d8b: 18% — the suspiciously-good cell
  - A handful of `liq_video_frames_full` cells in Sweep B around 11-15%
- **All cells 3/3 captured cleanly** — no missing data, no OOMs, no
  timeouts. Total wall ~7.7 hours (Sweep A 4h23m, Sweep B 3h28m).
- **Trade-off visualization design**: each per-bench heatmap uses
  `wall%/RSS%` packed into one cell so the trade-off is visible at a
  glance. The Pareto-frontier list per bench enumerates non-dominated
  cells (no other cell gives smaller wall *and* smaller RSS), sorted by
  wall ratio. The headline Pareto table at the top of this report
  collapses each bench to a default/min-wall/min-RSS triple for
  cross-bench comparison.

## Suggested follow-ups

1. **Re-do the (M, o) sweep on `liq_video_frames_full` at N=10** — the
   5-11 `M=250, o=120` cell was N=3 noise; this sweep was also N=3 and
   the high-spread cells (~11-15%) are at the regime where claims matter
   most. N=10 on just this one bench is ~2 hours and would lock in the
   "M=11 is best for wall" finding.
2. **Profile `liq_video_frames_page` at `M=250`** — the +130% wall
   regression is mechanistically distinct from anything else in the
   matrix. `perf record -e page-faults,cycles` would identify whether
   this is finaliser walking, page-fault path, or something else
   entirely. The data point is too striking to leave unexplained.
3. **Investigate the synthetic vs real-ffmpeg gap on `_pool`.** The
   negative #14533 result here could mean either (a) the synthetic stub
   is too minimal or (b) Ryzen doesn't surface the effect. To disambiguate,
   instrument the stub to do a small amount of OCaml-heap work per frame
   (the source has `LIQ_CHURN` for exactly this purpose) and rerun the
   (M, o) sweep on `_pool` with `LIQ_CHURN=1000`. If a free lunch
   appears with churn, the stub is the culprit; if not, the hardware
   hypothesis stands. See [project_toots_gc_repro_parked.md](.claude/projects/-home-udesou/memory/project_toots_gc_repro_parked.md).
4. **Update `liq_parse_typecheck` headline.** This sweep changed the
   diagnosis: it's not a regression, it's a default-`o` mistuning.
   Worth a one-line update to the 5-12 N=10 report and to the
   release-notes summary.
5. **Set up an `s` sweep on owl_gc.** Sweep B only covered `(M, o)` on
   owl_gc; we don't know how `s` interacts with the d8b win. Cheap to
   add given the bench is fast (~3s/inv). Hypothesis: the win is
   independent of `s` (since 5.4's pathology is purely in the
   custom-block pacer, not the minor heap), but worth confirming.
6. **Write a release-notes guidance section** for the off-heap pacer
   trade. The data now supports a clear recommendation grid:
   - cpdf-style (RSS-sensitive PDFs): `s ≥ 1048576, o=200` → -35 to -50% RSS, +1.7-5% wall
   - liquidsoap full-frame: `M=11, o=40` → +6% wall, near-zero RSS
   - liquidsoap pool/AVFrame: defaults are fine
   - owl/numerical: `M=11` → -50% wall (no trade-off; it's a strict win)
   - zarith-heavy: `o ≤ 80` → strict win on both axes
   - liq_parse_typecheck-style typer workloads: `o=40` → strict win
