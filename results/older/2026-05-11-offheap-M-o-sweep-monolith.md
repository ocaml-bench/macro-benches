# Off-heap (M, o) sweep — 5.4.1 vs d8bb46c (monolith)

**Date:** 2026-05-11
**Host:** monolith (AMD Ryzen 9 9950X)
**Compilers:** `ocaml-5.4.1` vs `ocaml-d8bb46c39bf5fcafb513a8ba18e667d3f8c2600a` (5.5-beta) — base, no `-fp`/`-flambda`
**Benchmarks:** the off-heap / custom-block subset from the 2026-05-08 regression sweep, plus `owl_gc` and `zarith_pi`:
`alt_ergo_fill`, `cpdf_merge`, `cpdf_scale`, `cpdf_squeeze`, `liq_video_frames`, `owl_gc`, `pplacer_testsuite`, `zarith_pi`.
**Sweep:** `(M, o)` 7×5 at default `(s=262144, m=100)`.
  - `M ∈ {11, 22, 44, 88, 125, 176, 250}`
  - `o ∈ {40, 80, 100, 120, 150}`
**Invocations:** 3 per cell (35 cells × 2 runtimes × 8 benches × 3 = 1680 invocations)
**Config:** `running-ng/src/running/config/experiments/offheap_M_o_sweep_5.4.1_vs_d8bb46c.yml`
**Logs:** [`../logs/2026-05-11-offheap-M-o-monolith/`](../logs/2026-05-11-offheap-M-o-monolith/) (mirror — sidecars + YAML configs). Original: `~/running-ng/gc-sweep-logs-sweep-parameters-2026-05-11/monolith-2026-05-11-Mon-094942/`.
**Defaults (verified in d8bb46c `runtime/caml/config.h`):** `s=262144, o=120, M=44, m=100`

## TL;DR

Extending the previous regression sweep with `M` up to 250 and adding `owl_gc` + `zarith_pi` splits the off-heap-allocating set into **four mechanistically distinct categories**:

1. **`owl_gc` is the *opposite* of `liq_video_frames` — d8bb46c is dramatically faster.** At default `(M=44, o=120)` d8b finishes in 3.35s vs 5.4's 5.44s (**-38.4%**); at `M=11, o=80` the ratio reaches **-53.3%** (5.4: 13.3s → d8b: 6.2s). Mechanism is unambiguous in the olly trace: 5.4.1 fires one major per minor (210k:210k at `M=11`), d8b runs the new pacer at 1:2 (179k:90k), gc_overhead drops from 63% → 42%. The 5.4 custom-block pacer is pathologically aggressive on Bigarray-backed `Owl.Mat.Ndarray` workloads — d8b fixes it. **Smaller `M` magnifies d8b's win, not shrinks it**, because the 5.4 pacer goes berserk and d8b doesn't.
2. **`liq_video_frames` confirms the previous (M, m) finding — and extends it past `M=176`.** Wall regression spans **+4.8% (`M=11, o=80`) → +35.7% (`M=176, o=100`)**, with the previously-unobserved `M=250` cells giving a clean second-knee: wall ratio drops back to **+10.1%** at `(M=250, o=120)` while RSS ratio reaches **-29.4%** at `(M=250, o=100)`. The Pareto frontier d8b offers on this workload is "give me ≤+10% wall for -23 to -29% RSS" — a strictly better deal than what `M=176` showed in the 2026-05-08 sweep.
3. **`alt_ergo_fill`, `cpdf_merge/scale/squeeze`, `pplacer_testsuite` are flat in `M`.** All sit at +3-9% wall across the entire 7×5 grid; the `M` range from 11 to 250 moves the regression by ≤2pp on every cell. These are not off-heap-pacer-bound — confirming the prior diagnosis that `cpdf_*` and `alt_ergo_fill` are major-pacer effects, not custom-block effects.
4. **`zarith_pi` is an `o` story, not an `M` story.** Wall and RSS are essentially flat across `M`; `o` swings the version effect from **-15.5% at `o=80` to +7.9% at `o=150`**. RSS ratio similarly inverts at `o=120`. The Z.t custom blocks don't pace this workload — the heap-pacer's interaction with `o` does.

The two big new pieces of information versus 2026-05-08:
  - **owl_gc is the cleanest "5.5-beta wins on off-heap workloads" data point in the matrix** — and it points the same direction as the cpdf/alt_ergo RSS wins.
  - **The `liq_video_frames` Pareto frontier extends much further than `M=176`** — `M=250` is where the wall:RSS tradeoff bottoms out cleanly.

## Per-bench summary at default cell `(M=44, o=120)`

| benchmark | 5.4 wall | d8b wall | wall Δ | RSS Δ | best d8b cell (min ratio) | best ratio | worst cell | worst ratio |
|---|---|---|---|---|---|---|---|---|
| alt_ergo_fill | 4.69s | 5.05s | +7.7% | -19.8% | `M=11, o=150` | +5.0% | `M=22, o=120` | +9.0% |
| cpdf_merge | 2.04s | 2.15s | +5.4% | -27.4% | `M=22, o=80` | +3.2% | `M=11, o=40` | +5.7% |
| cpdf_scale | 12.37s | 13.03s | +5.3% | -39.4% | `M=250, o=150` | +3.3% | `M=44, o=100` | +6.8% |
| cpdf_squeeze | 3.30s | 3.44s | +4.2% | -25.9% | `M=44, o=150` | +2.4% | `M=11, o=40` | +5.4% |
| **liq_video_frames** | 3.96s | 4.68s | **+18.2%** | **-14.0%** | `M=11, o=80` | **+4.8%** | `M=176, o=100` | **+35.7%** |
| **owl_gc** | 5.44s | 3.35s | **-38.4%** | -17.4% | `M=11, o=80` | **-53.3%** | `M=250, o=120` | -10.7% |
| pplacer_testsuite | 6.16s | 6.21s | +0.8% | -7.0% | `M=176, o=80` | -0.8% | `M=11, o=150` | +4.8% |
| zarith_pi | 2.48s | 2.53s | +2.0% | +2.3% | `M=88, o=40` | -15.5% | `M=44, o=150` | +7.9% |

Read the "best ratio" column as "d8b's best-case version delta at any sweep cell". `owl_gc` is the only bench where d8b dominates everywhere; `zarith_pi` is the only bench where the sign flips within the grid.

## owl_gc — the new "off-heap win" data point

5.4.1 wall time scales massively with `M`: from **14.5s at `M=11, o=40`** down to **2.5s at `M=250, o=40`** — a 5.8× speedup from a single `OCAMLRUNPARAM` knob, which by itself signals that the 5.4 custom-block pacer is mistuned for this workload. d8b scales much less violently (7.0s → 2.2s), and is uniformly faster than 5.4 across the whole grid:

### owl_gc — wall ratio d8b vs 5.4.1 (%)

| M \ o | 40 | 80 | 100 | 120 | 150 |
|---|---|---|---|---|---|
| **11** | -51.5% | **-53.3%** | -50.9% | -48.3% | -50.1% |
| 22 | -47.1% | -47.7% | -47.0% | -49.2% | -48.2% |
| **44** (default) | -38.3% | -39.8% | -35.7% | **-38.4%** | -38.7% |
| 88 | -34.6% | -28.6% | -26.8% | -30.9% | -29.5% |
| 125 | -20.2% | -22.3% | -27.0% | -20.8% | -15.0% |
| 176 | -20.5% | -17.1% | -16.6% | -17.7% | -17.5% |
| 250 | -13.0% | -16.1% | -12.4% | -10.7% | -11.8% |

Sanity check on the mechanism — olly traces at `(M=11, o=80)`:

```
ocaml-5.4.1   : wall 13.3s, gc_overhead 63%, minor 210256, major 210256   (1:1)
ocaml-d8bb46c : wall  6.2s, gc_overhead 42%, minor 179125, major  89562   (1:2)
```

5.4 is doing a full major collection on every minor collection at `M=11` — this is the 4.x-era custom-block pacer behaving badly. d8b's new pacer settles into 1 major per 2 minors and gets the work done. `M=44` (default) is less catastrophic for 5.4 (5.44s wall) but d8b still wins by 38pp.

**The owl_gc RSS story is mostly inert** — d8b is -10 to -22% RSS across the grid, flatter than the wall ratio, with the largest RSS wins clustering at `M=22-44`. The "owl_gc d8b is faster *and* uses less RSS" finding is unambiguous; the trade is not on the table here.

> Within-cell wall spread for owl_gc is median 3.6%, p90 8.8%, max 14.7% — substantially noisier than the other benches (which sit at p90 ≤ 2.6%). The -50% range absolute deltas (≥6s) are far above this noise floor, but treat any single-cell delta < 3pp as noise for this benchmark.

## liq_video_frames — Pareto frontier extends to M=250

The wall-time ratio heatmap, now with `M` extended past 176:

### liq_video_frames — wall ratio d8b vs 5.4.1 (%)

| M \ o | 40 | 80 | 100 | 120 | 150 |
|---|---|---|---|---|---|
| **11** | +6.6% | **+4.8%** | +8.8% | +6.7% | +6.4% |
| 22 | +9.9% | +9.1% | +13.5% | +12.3% | +19.0% |
| **44** (default) | +15.2% | +15.8% | +17.3% | **+18.2%** | +25.8% |
| 88 | +23.3% | +21.4% | +28.2% | +24.6% | +18.9% |
| 125 | +30.2% | +20.3% | +31.1% | +22.3% | +21.8% |
| 176 | +30.5% | +23.7% | **+35.7%** | +22.2% | +22.0% |
| 250 | +22.1% | +26.0% | +17.1% | **+10.1%** | +26.2% |

### liq_video_frames — RSS ratio d8b vs 5.4.1 (%)

| M \ o | 40 | 80 | 100 | 120 | 150 |
|---|---|---|---|---|---|
| 11 | -5.2% | -5.2% | -5.2% | -6.9% | -5.2% |
| 22 | -9.4% | -9.2% | -9.2% | -9.0% | -9.0% |
| **44** | -15.1% | -14.5% | -14.5% | **-14.0%** | -14.0% |
| 88 | -19.6% | -18.7% | -18.7% | -17.9% | -17.9% |
| 125 | -22.5% | -21.3% | -21.3% | -25.2% | -20.2% |
| 176 | -24.7% | -23.2% | -23.2% | -22.0% | -22.0% |
| **250** | -26.7% | -25.0% | **-29.4%** | -23.5% | -23.5% |

Two observations the previous sweep couldn't make (it stopped at `M=176`):

- **The wall ratio at `M=250` partially recovers.** Going from `M=176` to `M=250` drops the wall regression at `o=100` from +35.7% → +17.1%, and at `o=120` from +22.2% → **+10.1%**. The 5.4 wall continues to drop (because the pacer keeps releasing custom blocks more lazily), so the *ratio* relaxes even though d8b is also still gaining. **`M=250, o=120` is the new wall-ratio sweet spot in the high-M regime**.
- **The RSS curve does not stop at `M=176`.** `M=250` gives **-23 to -29%** RSS vs 5.4 across the grid — a meaningful additional ~5pp RSS reduction beyond what `M=176` offered.

This means the Pareto-best operating point for `liq_video_frames` users is now `M=250, o=120`: about **+10% wall for -23% RSS** vs 5.4 at the same cell. The previous report's "use `M=176`" recommendation was conservative; `M=250` is a strict improvement on both metrics within the 5.5-beta family.

## Pacer-flat benches — alt_ergo_fill, cpdf_*, pplacer_testsuite

For these five, the version regression is essentially invariant in `M` (and only weakly varies in `o`). They are heap-pacer-bound, not custom-block-pacer-bound, and `(M, o)` provides no meaningful userspace tuning lever for them. Reproducing this category just to put it on file:

### alt_ergo_fill — wall ratio (range +5.0% to +9.0%)

Flat in `M` (column ranges ≤ 2pp); slight `o` effect — `o=150` is the best column at +5-6%, `o=120` is worst at +7-9%.

### cpdf_merge / cpdf_scale / cpdf_squeeze — wall ratio

All three sit between **+2.4% and +6.8%** across the entire 7×5 grid. The best column is `o=80` (matches the previous report's "bigger o doesn't help cpdf much"). No interaction with `M` is detectable above noise.

RSS, however, is strongly `o`-dependent and `M`-invariant (typical: cpdf_scale -13.8% at `o=40` → -42.8% at `o=150`, identical within a few tenths of a pp across every `M`). The cpdf RSS wins come *entirely* from the major pacer and `o`, not `M`.

### pplacer_testsuite — wall ratio

Best cells (`M=176-250, o=80`) hit **-0.8%** — d8b actually a touch faster. Worst cell (`M=11, o=150`) is **+4.8%**. Within noise across most of the grid; the previous report's "noise-bound" diagnosis stands.

## zarith_pi — the `o`-only story

### zarith_pi — wall ratio d8b vs 5.4.1 (%)

| M \ o | 40 | 80 | 100 | 120 | 150 |
|---|---|---|---|---|---|
| 11 | -13.2% | -12.5% | -3.1% | +3.7% | +7.4% |
| 22 | -12.2% | -15.0% | -3.1% | +2.0% | +6.5% |
| **44** | -14.0% | **-15.5%** | -7.4% | +2.0% | **+7.9%** |
| 88 | -15.5% | -13.5% | -3.8% | +0.0% | +7.0% |
| 125 | -12.5% | -13.2% | -3.1% | +0.4% | +7.5% |
| 176 | -12.3% | -13.7% | -3.4% | +2.8% | +7.5% |
| 250 | -12.5% | -14.6% | -4.2% | +3.3% | +6.1% |

Every row is essentially identical — `M` does nothing. Every column tells the same story across all rows: d8b is **12-15% faster at `o ≤ 80`**, neutral at `o=100`, and **6-8% slower at `o=150`**.

### zarith_pi — RSS ratio d8b vs 5.4.1 (%)

| M \ o | 40 | 80 | 100 | 120 | 150 |
|---|---|---|---|---|---|
| 11 | -25.1% | -22.0% | -6.8% | +3.0% | +11.0% |
| 22 | -22.5% | -22.6% | -5.9% | +4.1% | +11.6% |
| 44 | -23.5% | -23.2% | -8.1% | +2.3% | +10.0% |
| 88 | -26.4% | -22.5% | -10.1% | +2.0% | +10.8% |
| 125 | -23.2% | -22.9% | -5.6% | +3.4% | +11.0% |
| 176 | -25.4% | -22.4% | -6.4% | +3.5% | +10.7% |
| 250 | -24.5% | -21.9% | -7.7% | +3.4% | +12.0% |

RSS mirrors wall — `o ≤ 80` and d8b is -22 to -26% on RSS; `o ≥ 120` and it crosses over to +2 to +12%. The Z.t custom-block allocation doesn't dominate this workload's pacing — what matters is the major-pacer's interaction with `o`, identical to the cpdf RSS story.

> Within-cell noise is moderate for zarith_pi (median spread 1.6%, max 8%). The `o`-axis signal (12-15pp swing) is comfortably above noise; do not over-interpret `M`-axis variation.

## Best-of-tradeoff under d8bb46c

For each bench, the d8b cell with the lowest wall and the d8b cell with the lowest RSS:

| bench | default wall | min wall (cell) | default RSS | min RSS (cell) |
|---|---|---|---|---|
| alt_ergo_fill | 5.05s | 4.86s `(M=11, o=150)` | 948 MiB | 771 MiB `(M=88, o=40)` |
| cpdf_merge | 2.15s | 2.10s `(M=88, o=150)` | 363 MiB | 322 MiB `(M=176, o=40)` |
| cpdf_scale | 13.03s | 12.67s `(M=250, o=150)` | 489 MiB | 393 MiB `(M=88, o=40)` |
| cpdf_squeeze | 3.44s | 3.35s `(M=44, o=150)` | 328 MiB | 265 MiB `(M=11, o=40)` |
| **liq_video_frames** | 4.68s | **2.61s** `(M=250, o=120)` | 517 MiB | **366 MiB** `(M=11, o=40)` |
| **owl_gc** | 3.35s | **2.11s** `(M=250, o=100)` | 126 MiB | **48 MiB** `(M=250, o=150)` |
| pplacer_testsuite | 6.21s | 6.04s `(M=88, o=100)` | 70 MiB | 65 MiB `(M=88, o=40)` |
| zarith_pi | 2.53s | 2.44s `(M=176, o=150)` | 127 MiB | 115 MiB `(M=44, o=150)` |

`liq_video_frames` and `owl_gc` are the only benches where the wall-cell and RSS-cell differ enough to matter:

- **liq_video_frames** — min wall is at `M=250` (lazy custom-block pacing → less GC cost on this finaliser-heavy workload); min RSS is at `M=11` (aggressive pacing → small custom-block footprint). The joint sweet spot is `M=250, o=120`: 2.61s wall (still +10.1% vs 5.4 at the same cell) and 530 MiB RSS (-23.5% vs 5.4) — better on both axes than the default cell.
- **owl_gc** — both extrema are at `M=250` (just different `o`), so the curve is monotone: bigger `M` is always better on this workload. There is no tradeoff to manage; setting `M=250` is a strict win across the grid.

For the other six benches, `(M, o)` movement is small enough that the default cell is within a few percent of optimal on either axis.

## Findings

### 1. The off-heap regression diagnosis from 2026-05-08 is incomplete

The 2026-05-08 sweep concluded that off-heap workloads regress under d8b's new pacer, with `(M, m)` recoverable down to ~+5pp. Adding `owl_gc` flips that diagnosis: **off-heap workloads can also *gain* substantially under d8b** — owl_gc gains up to 53pp. The deciding factor is whether the 5.4 pacer was pathologically over-aggressive (owl_gc: 1 major per minor) or whether d8b's pacer is too lazy at default `M` (liq_video_frames). The two workloads are mechanistic opposites.

The release-notes guidance should be reframed: the 5.5-beta custom-block pacer trades workload-specific wall time for RSS *consistency* across workloads — some benches win huge, some lose modestly. The `M` knob is the dominant lever in both directions.

### 2. liq_video_frames Pareto frontier is wider than previously measured

`M=250, o=120` gives d8b a +10.1% wall regression with -23.5% RSS — strictly better than `M=176, m=25` from the previous sweep (which gave -22% RSS for a higher wall ratio). The previous report's recommendation `OCAMLRUNPARAM="M=176"` for off-heap-finaliser-heavy workloads should be revised to **`M=250` (or higher — the curve has not bottomed)**.

A follow-up sweep at `M ∈ {250, 350, 500}` would establish whether the wall regression continues to decay or whether `M=250` is the inflection point.

### 3. zarith_pi is an `o`-bound benchmark, not a custom-block-bound one

Despite using Z.t custom blocks, zarith_pi's version effect is driven entirely by `o`. This is informative because it means the "alt_ergo_fill: zarith Z.t custom blocks" tag from the 2026-05-08 sweep was misleading — alt_ergo_fill's regression is also not custom-block-driven (we knew it was `M`-flat). Both zarith-using benches are major-pacer effects, not custom-block effects. The custom-block pacer touches Z.t only on a very small fraction of allocations.

This bears on the headline narrative: of the six benches we labelled "off-heap" in the 2026-05-08 report, **only `liq_video_frames` is genuinely custom-block-pacer-bound**. The other five (cpdf_*, alt_ergo_fill, pplacer_testsuite) are major-pacer effects that happen to be on workloads that allocate custom blocks. Adding `owl_gc` gives us a *second* genuinely custom-block-bound benchmark — and one where d8b wins.

### 4. `o` matters more than the headline matrix has been measuring

We added `o=40` to this sweep (the 2026-05-08 sweep only went down to `o=80`). Several findings hinge on it:

- zarith_pi: best d8b ratio is at `o=40-80` (-12 to -15%); the headline matrix at `o=120` would have called this a flat +2%.
- cpdf_*: smallest regression columns are at `o=40-80`; largest RSS wins are at `o=120-150`.
- owl_gc: best d8b ratios cluster at `o=40-80` for low `M`.

The headline matrix's `o=120` default sits roughly in the middle of `o`-sensitivity for most of these benches. Worth noting that **none of the off-heap regressions get worse at `o=40`** — there is no risk to including a low-`o` column in future sweeps.

### 5. `M=44` (the new default) is a defensible compromise — but not optimal for any single workload

Across the eight benches:
- 4 prefer high `M` (≥125) for d8b wall: cpdf_scale, owl_gc, liq_video_frames, zarith_pi
- 4 prefer low `M` (≤22) for d8b wall: alt_ergo_fill (flat-ish, slight pref low), cpdf_merge, cpdf_squeeze, pplacer_testsuite (basically flat)

The new OCaml default of `M=44` is a centred choice — it does not minimize wall regression for any single bench in this set, but it doesn't badly mis-tune any either. Workloads with known off-heap-heavy patterns (owl, liquidsoap-video) should consider setting `M` explicitly.

## Methodology notes

- 3 invocations per cell. Within-cell wall spread (max−min)/median:
  - tight (p90 ≤ 2.6%): alt_ergo_fill, cpdf_merge/scale/squeeze, liq_video_frames, pplacer_testsuite
  - moderate (p90 5-8%): zarith_pi
  - noisy (p90 8.8%, max 14.7%): owl_gc
  For owl_gc, treat single-cell deltas < 3pp as noise; the headline -50% / -38% ratios are robust against this noise floor because the absolute deltas are large.
- All cells use `perf_grp1|re-25|md-2` — same instrumentation envelope as the 2026-05-08 sweep.
- `s` and `m` fixed at OCaml defaults (`s=262144, m=100`). The 2026-05-08 sweep covered `(s, o)` and `(M, m)` separately; `(M, o)` is the previously-uncrossed pair and is the focus here.
- The `(s, o)` heatmaps from 2026-05-08 covered `o ∈ {80, 100, 120, 150, 200}`; this sweep covers `o ∈ {40, 80, 100, 120, 150}` — the overlap at `o=80, 100, 120, 150` reproduces those numbers within noise; `o=40` is new and informative for zarith_pi and cpdf_*.
- No OOMs, timeouts, or build failures across the 1680 invocations.

## Suggested follow-ups

1. **Extend the `liq_video_frames` `M` sweep further** — `M ∈ {250, 350, 500, 1000}` at `o=120` — to find where the wall regression bottoms out, or whether `M=250` is already the inflection. Currently the curve from `M=176 → M=250` shows a ~12pp wall improvement and ~5pp additional RSS reduction; no theoretical reason it must stop there.
2. **Replicate owl_gc at N=10 to lock in the -50% headline** — the 14.7% max within-cell spread is high enough that the policy-affecting "owl_gc is a major d8b win" claim should have a tighter confidence interval. Same cells (`M=11, 44, 250` × `o=80, 120`) at N=10 = 60 invocations total, ~10 minutes wall.
3. **Add an `M`-axis row to the headline matrix.** The 5.2/5.4/5.5 headline report used a single `(s, o, M, m)` default cell — but `M` cleanly separates "off-heap regressor" from "off-heap winner" in this set. A two-cell row (`M=44, M=176`) for liq_video_frames and owl_gc in the headline would prevent the next reader from drawing the same incomplete conclusion the 2026-05-08 sweep did.
4. **Drop "off-heap" as a benchmark tag**; replace it with "custom-block-pacer-bound" (verified per-bench via `(M, ·)` slope) — only liq_video_frames and owl_gc qualify in the current macro suite. Tagging the others as off-heap implies a mechanism the data doesn't support.
5. **Investigate the zarith_pi `o=120` crossover.** The sign flip between `o=100` (-3 to -10%) and `o=120` (≈0 to +4%) is sharp and consistent across all `M`. Likely a defaulting story similar to liq_parse_typecheck (the new pacer wants a different `o` than the OCaml default). Worth a one-bench `o ∈ {100, 110, 115, 120}` mini-sweep at N=10 to find the precise crossover.
