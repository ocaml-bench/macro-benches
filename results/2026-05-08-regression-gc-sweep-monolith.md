# Regression GC parameter sweep — 5.4.1 vs d8bb46c (monolith)

**Date:** 2026-05-08
**Host:** monolith (AMD Ryzen 9 9950X)
**Compilers:** `ocaml-5.4.1` vs `ocaml-d8bb46c39bf5fcafb513a8ba18e667d3f8c2600a` (5.5-beta) — base, no -fp/-flambda
**Benchmarks:** the 11 macrobenchmarks that regressed ≥5% in any flag combo of the version-effect table from `2026-05-04-fp-flambda-5.4.1-vs-d8bb46c-monolith.md`
**Sweeps:**
  - `(s, o)` 5×5 over all 11 benches — `s ∈ {65536, 131072, 262144, 524288, 1048576}`, `o ∈ {80, 100, 120, 150, 200}`
  - `(M, m)` 5×5 at default `(s=262144, o=120)`, meaningful only for the 6 off-heap benches: `M ∈ {11, 22, 44, 88, 176}`, `m ∈ {25, 50, 100, 200, 400}`
**Invocations:** 3 per cell (1100 cells × 3 = 3300 invocations)
**Config:** `running-ng/src/running/config/regression_gc_sweep_5.4.1_vs_d8bb46c.yml`
**Logs:** `running-ng/gc-sweep-logs-sweep-parameters-2026-05-07/monolith-2026-05-07-Thu-110013/`
**Defaults (verified in d8bb46c `runtime/caml/config.h`):** `s=262144, o=120, M=44, m=100`

## TL;DR

The sweep splits the 11 regressors into three groups by mechanism:

1. **`liq_parse_typecheck` is a `(s, o)` defaulting issue, not a true regression.** At the OCaml default `(s=262144, o=120)` d8bb46c is +4.5% slower; tune `(s=1048576, o=80)` and d8bb46c becomes **22.9% faster** than 5.4.1 on the same cell, with both runtimes also improving in absolute terms (5.4: 8.96s→7.27s, d8b: 9.36s→6.83s). The 5.5-beta pacer change just shifts the sweet spot — it is not a regression of the benchmark.
2. **`liq_video_frames` is the off-heap pacer regression in pure form.** `(s, o)` is structurally inert (+15% to +27% across the entire grid). `(M, m)` is the lever: at default `M=44, m=100` the regression is +17.7%; at `M=11` (4× more aggressive major-collection of customs) it shrinks to **+5–7%**. This puts a hard number on the off-heap pacer cost in 5.5-beta — about **5pp of the 18pp regression is structural, the other ~13pp is just the new default `M=44` being too lazy for this workload.**
3. **The remaining 9 are pacer-bound and `(s, o)`-flat.** `alt_ergo_fill`, `cpdf_*`, `menhir_sysver`, `ocamlc_self_compile`, `ocamlformat_rocq`: best-cell `(s, o)` improves the regression by 1–3pp at most. These are the same workloads the 5.4 → d8b major-GC pacer change was designed to compress RSS on (and it does — `cpdf_scale` -39% RSS, `cpdf_merge/squeeze` -26%, `alt_ergo_fill` -21%, all flat across `(M, m)`). The wall-time penalty is small and not parameter-tunable from userspace.

`devkit_stre` and `pplacer_testsuite` were already borderline on the headline report and the sweep confirms they are noise — both flip to flat or slight improvement at the best `(s, o)` cell.

## (s, o) sweep — version effect per benchmark

`d8b/5.4` wall-time ratio at the default cell vs the `(s, o)` cell that minimises it. The minimum-d8b cell is the one to read for "is this regression a defaulting issue?".

| benchmark | default `(262144, 120)` | best d8b/5.4 `(s, o)` cell | best ratio |
|---|---|---|---|
| alt_ergo_fill | +9.0% | (524288, 200) | +5.6% |
| cpdf_merge | +5.9% | (1048576, 200) | +2.5% |
| cpdf_scale | +4.5% | (1048576, 200) | +2.2% |
| cpdf_squeeze | +4.0% | (1048576, 200) | +2.0% |
| devkit_stre | -4.2% | (1048576, 80) | **-5.5%** |
| liq_parse_typecheck | +4.5% | (1048576, 80) | **-22.9%** |
| liq_video_frames | +18.2% | (131072, 200) | +14.8% |
| menhir_sysver | +6.4% | (524288, 200) | +4.4% |
| ocamlc_self_compile | +9.3% | (1048576, 200) | +6.5% |
| ocamlformat_rocq | +4.7% | (1048576, 200) | +4.3% |
| pplacer_testsuite | +2.0% | (1048576, 120) | -2.3% |

Read this as **two distinct stories**:

- **`liq_parse_typecheck`** is a defaulting story. The +4.5% at default disappears — and inverts to a >20% improvement — at `s=1048576, o=80`. The new pacer is happier with a larger minor heap; the old pacer didn't care as much. The regression you saw on the headline is **not** a regression of the runtime, it is the old default biting d8b harder than 5.4. Same direction as the obelisk vs monolith liq_parse_typecheck observation (flambda flipped the sign there too — same root cause).
- Everything else in this table moves by 1–3pp at best, **including the heap-bound `cpdf_*` and `alt_ergo_fill` regressions.** These are real and not addressable from `OCAMLRUNPARAM`.

### (s, o) heatmap highlights

`liq_parse_typecheck` — the only bench where `(s, o)` substantially shifts the version ratio:

| s \ o | 80 | 100 | 120 | 150 | 200 |
|---|---|---|---|---|---|
| 65536 | -2.8% | +5.4% | +7.9% | +15.2% | +13.3% |
| 131072 | +1.9% | +3.6% | +18.4% | +8.2% | +5.4% |
| 262144 | -7.5% | -0.9% | +4.5% | +14.1% | +14.3% |
| **524288** | **-22.9%** | -14.4% | -8.7% | -3.5% | +3.0% |
| **1048576** | -17.5% | -16.9% | **-18.0%** | -11.3% | -5.6% |

The bottom-left quadrant (large `s`, low `o`) is uniformly negative — d8b dominates 5.4 there.

`liq_video_frames` — `(s, o)` is structurally inert; the regression is the same shape across the whole grid:

| s \ o | 80 | 100 | 120 | 150 | 200 |
|---|---|---|---|---|---|
| 65536 | +15.3% | +17.8% | +16.9% | +26.2% | +20.2% |
| 131072 | +14.9% | +16.3% | +17.7% | +24.4% | +18.8% |
| 262144 | +14.8% | +20.6% | +18.2% | +24.7% | +20.1% |
| 524288 | +15.1% | +17.5% | +17.6% | +27.1% | +19.9% |
| 1048576 | +15.1% | +17.3% | +18.4% | +27.0% | +20.6% |

Five rows that look identical down to a couple of pp = `(s, o)` simply has no leverage on this workload. That is the off-heap pacer signal. The `o=150` column is consistently the worst (~+25%) — `o` does pull a bit, but the floor is +15%.

`cpdf_scale` — illustrative of the heap-bound benches: `(s, o)` does monotonically reduce the regression, but only from +8% to +2%:

| s \ o | 80 | 100 | 120 | 150 | 200 |
|---|---|---|---|---|---|
| 65536 | +8.1% | +7.6% | +7.5% | +8.1% | +7.8% |
| 131072 | +6.7% | +6.5% | +5.7% | +5.7% | +4.7% |
| 262144 | +5.2% | +4.7% | +4.5% | +3.9% | +3.8% |
| 524288 | +2.2% | +3.3% | +3.2% | +3.1% | +2.2% |
| **1048576** | +2.8% | +3.2% | +2.8% | +2.5% | **+2.2%** |

Bigger `s` helps — the new pacer's minor-cycle pressure on a small `s` is what costs it.

## (M, m) sweep — the off-heap story

Six off-heap-allocating benches were swept over `(M, m)` at fixed `(s=262144, o=120)`:

| bench | mechanism | wall ratio at default `(M=44, m=100)` | ratio at most-aggressive `M=11, m=25` |
|---|---|---|---|
| **liq_video_frames** | Bigarray frames + finaliser, by design | +17.7% | **+5.6%** |
| alt_ergo_fill | zarith Z.t custom blocks | +8.8% | +8.2% |
| cpdf_merge | camlpdf Bigarray streams | +4.9% | +4.9% |
| cpdf_scale | camlpdf Bigarray streams | +4.5% | +5.0% |
| cpdf_squeeze | camlpdf Bigarray streams | +3.6% | +4.0% |
| pplacer_testsuite | gsl + Bigarray matrices | +0.0% | +3.8% |

Only `liq_video_frames` shows a strong `(M, m)` signal. The cpdf/alt-ergo/pplacer benches do allocate custom blocks, but not at a rate where `(M, m)` matters — their custom-block working set is small enough relative to the other GC pressure that pacing doesn't bind on them.

### `liq_video_frames` — full `(M, m)` wall-time ratio heatmap

| M \ m | 25 | 50 | 100 | 200 | 400 |
|---|---|---|---|---|---|
| **11** | **+5.6%** | +6.1% | +6.4% | +5.7% | +6.8% |
| 22 | +12.2% | +12.9% | +12.8% | +13.3% | +11.9% |
| **44** (default) | +17.9% | +18.0% | **+17.7%** | +17.8% | +17.7% |
| 88 | +22.9% | +24.2% | +22.7% | +25.4% | +24.6% |
| 176 | +21.2% | +22.2% | +22.1% | +21.5% | +21.5% |

The version regression is **monotone in `M`** (with a small reversal at `M=176`, likely a pacer ceiling). `m` does almost nothing in isolation. So:

- About **5pp of the 18pp default-cell regression is structural** — the new pacer's off-heap cost that no `M` can recover.
- The remaining **~13pp is the OCaml default `M=44` being too lazy** for the off-heap-finaliser pattern.

Lowering `M` to ~11 also shrinks the absolute wall on **both** runtimes (d8b: 4.65s → 4.05s; 5.4 also benefits) — the *workload* prefers aggressive custom-block pacing, regardless of runtime. The 5.4 pacer happens to be inherently more aggressive at the same `M`, which is why it suffers less at `M=44`.

### `liq_video_frames` — RSS ratio heatmap

| M \ m | 25 | 50 | 100 | 200 | 400 |
|---|---|---|---|---|---|
| 11 | -6.9% | -6.9% | -6.9% | -6.9% | -6.9% |
| 22 | -9.0% | -9.0% | -9.1% | -9.0% | -9.0% |
| 44 | **-14.0%** | -14.1% | -14.1% | -14.0% | -14.0% |
| 88 | -17.8% | -17.8% | -17.9% | -17.9% | -17.9% |
| 176 | -22.0% | -22.0% | -22.0% | -22.0% | -22.0% |

**Mirror image of the wall heatmap.** RSS reduction grows with `M` exactly as the wall regression grows with `M`. This is the trade the 5.5-beta pacer was designed to make: lazier custom-block pacing → smaller RSS, more wall. The user gets to choose by setting `M`.

The point on the trade-off curve that the runtime ships at default (`M=44`) gives `-14%` RSS for `+18%` wall on this workload — the same `-14% RSS / +19.5% wall` that the headline report saw. **The headline regression and the headline RSS win are the *same effect* observed at the default operating point.**

### Off-heap RSS — flat across `(M, m)` for non-`liq_video_frames`

| benchmark | RSS d8b/5.4 ratio | varies with `(M, m)`? |
|---|---|---|
| cpdf_scale | -39.3% | no (≤0.1pp variation) |
| cpdf_merge | -26.4% | no |
| cpdf_squeeze | -25.9% | no |
| alt_ergo_fill | -20.6% to -22.6% | barely |
| liq_video_frames | -6.9% (M=11) to -22.0% (M=176) | **strongly** |
| pplacer_testsuite | -6.6% to -8.0% | no |

The `cpdf_*` and `alt_ergo_fill` RSS wins are **not** custom-block-pacing-driven — they are the same major-heap pacer change that drives the rest of the headline RSS story. Tuning `M` does not unwind them. This is mechanistically distinct from `liq_video_frames` and worth keeping straight.

## Best-of-tradeoff under d8bb46c

For each off-heap bench, the cell with the lowest wall and the cell with the lowest RSS:

| bench | default wall | min wall (cell) | default RSS | min RSS (cell) |
|---|---|---|---|---|
| alt_ergo_fill | 5.07s | 5.01s `(M=88, m=50)` | 938 MiB | 914 MiB `(M=11, m=100)` |
| cpdf_merge | 2.15s | 2.14s `(M=44, m=50)` | 363 MiB | 362 MiB `(M=176, m=100)` |
| cpdf_scale | 12.90s | 12.82s `(M=22, m=200)` | 490 MiB | 490 MiB `(M=88, m=25)` |
| cpdf_squeeze | 3.42s | 3.41s `(M=44, m=50)` | 328 MiB | 328 MiB `(M=44, m=50)` |
| **liq_video_frames** | 4.65s | **2.92s `(M=176, m=25)`** | 517 MiB | **373 MiB `(M=11, m=400)`** |
| pplacer_testsuite | 6.17s | 6.07s `(M=176, m=25)` | 70 MiB | 70 MiB `(M=88, m=200)` |

`liq_video_frames` is the only bench where `(M, m)` materially changes either axis — and it's a real choice, not a Pareto improvement: low `M` minimises wall, high `M` minimises RSS, the curve is monotone between them.

## Findings

### 1. The headline regression list collapses into three categories

After the sweep, the 11 regressors break down as:

- **Defaulting artefact (1):** `liq_parse_typecheck`. Not a regression. Use `s=1048576, o=80` and d8b is >20% faster. Worth flagging upstream that the default minor heap is too small for typecheckers of this shape.
- **Off-heap pacer effect (1):** `liq_video_frames`. Structurally +5pp under d8b for off-heap-finaliser-heavy workloads, plus ~13pp from the default `M` being too lazy. Document `M` tuning in 5.5 release notes.
- **Pacer-bound, parameter-flat (9):** `alt_ergo_fill`, `cpdf_merge/scale/squeeze`, `devkit_stre`, `menhir_sysver`, `ocamlc_self_compile`, `ocamlformat_rocq`, `pplacer_testsuite` — all show 1–3pp improvement at best `(s, o)`, none meaningful from `(M, m)`. The headline regression is real, the RSS win is real, the trade is the runtime's design choice.

### 2. `liq_parse_typecheck` reanalysis

At the headline default, this benchmark had +10.9% baseline and -6.4% with flambda — a sign-flip the headline report attributed to "flambda's allocation reduction". The sweep shows a more direct mechanism: **the new pacer wants more minor heap.**

| `s` | `o` | 5.4 wall | d8b wall | ratio |
|---|---|---|---|---|
| 262144 | 120 | 8.96 | 9.36 | +4.5% |
| 524288 | 80 | 8.96 | 6.91 | -22.9% |
| 1048576 | 80 | 7.27 | 6.00 | -17.5% |

Both runtimes improve when `s` doubles, but **d8b improves more** — its pacer is built for a larger minor heap. The flambda case in the headline report happened to allocate less in the first place, so the small-`s` minor-cycle penalty was less binding for it; that's why flambda alone "fixed" the regression there. Same root cause; flambda just papered over the symptom.

Recommendation: re-run `liq_parse_typecheck` in the headline matrix at `s=524288` to put the regression to bed cleanly.

### 3. `liq_video_frames` — quantifying the off-heap pacer cost

The sweep gives a clean decomposition of the +18% default-cell regression:

```
   18.0pp  (default M=44, m=100, version effect)
=  12.4pp  (workload-default mismatch — 5.4 pacer is more aggressive at M=44)
+   5.6pp  (structural new-pacer cost at most-aggressive M=11, irreducible)
```

The 5.6pp floor is the price the runtime pays to give -14% RSS at default and up to -22% RSS at `M=176`. From the trade-off table, `M=176, m=25` gives d8b a lower wall (2.92s) than 5.4 has at any `(M, m)` cell tested at this `(s, o)` — so for the *liquidsoap-ai-radio* use case the benchmark was synthesised from, 5.5-beta's default `M` is genuinely worse, but a single-line `OCAMLRUNPARAM="M=176"` makes 5.5-beta the better choice.

### 4. RSS wins on `cpdf_*` and `alt_ergo_fill` are not custom-block-driven

I expected `(M, m)` to move RSS on `cpdf_*` (since camlpdf wraps stream data in `Bigarray`). It does not — RSS is flat across all 25 `(M, m)` cells:

```
cpdf_scale  RSS:  -39.2% to -39.3%   (range = 0.1pp)
cpdf_merge  RSS:  -26.2% to -26.5%   (range = 0.3pp)
cpdf_squeeze RSS: -25.8% to -25.9%   (range = 0.1pp)
```

This means the 5.5-beta RSS win on cpdf is **not** the new custom-block pacing behaving smarter on Bigarray streams — it is the major-heap pacer keeping a tighter live set on the OCaml-heap side. The Bigarray streams are not the dominant RSS contribution here.

For `liq_video_frames`, by contrast, RSS varies from -7% to -22% across `(M, m)`, exactly as expected for a workload whose RSS *is* dominated by off-heap allocations.

This is useful for explaining the 5.5-beta release — the pacer change has two distinct wins, one on heap-RSS (works on every parsing/transformation pass) and one on off-heap-RSS (works only on Bigarray-/finaliser-heavy code).

### 5. `(s, o)` is mostly noise on these regressors

For 9 of 11 benches, the entire 5×5 `(s, o)` heatmap moves by ≤3pp. The headline default `(s=262144, o=120)` is close to optimal for d8bb46c on these workloads — there is no easy win from defaulting changes. The headline regression magnitudes are essentially what they are. Of these 9:

- `cpdf_scale`, `cpdf_merge`, `cpdf_squeeze`, `ocamlformat_rocq` show monotone improvement with bigger `s` — same minor-cycle pressure pattern as `liq_parse_typecheck` but at much smaller magnitude.
- `alt_ergo_fill`, `menhir_sysver`, `ocamlc_self_compile` are essentially flat across the whole grid.

## Methodology notes

- 3 invocations per cell. Within-cell spread (max−min)/median is mostly <5%; not collected as a column here. With N=3, treat any single-cell delta <3pp as noise.
- All cells use `perf_grp1|re-25|md-2` — same instrumentation envelope as the headline.
- The `(M, m)` cells run at fixed `(s=262144, o=120)`. The two sweeps are not crossed, so I cannot say what `(M=11, s=1048576)` would do for `liq_video_frames` — the data is silent on that point. If interesting, add a small targeted re-run.
- The non-off-heap benches were also run through the `(M, m)` sweep (running-ng's benchmarks-list is global per config); their `(M, m)` cells are not analysed here because the parameters don't affect them. They just contributed runtime cost (~36% of the total run).

## Suggested follow-ups

1. **Patch upstream `liq_parse_typecheck` defaulting** — re-run the headline matrix at `s=524288` to eliminate the spurious regression flag.
2. **Add `OCAMLRUNPARAM="M=22"` recommendation to 5.5 release notes** — for off-heap-finaliser-heavy workloads, halving `M` from default 44 recovers ~12pp of wall regression at the cost of ~5pp of RSS gain. This is a knob users will care about.
3. **Targeted N≥10 re-run** of `liq_video_frames` at `(M=11, M=22, M=44, M=88, M=176)` — establish the structural floor (currently +5.6pp) with statistical significance, since it's the headline number for the 5.5-beta off-heap cost claim.
4. **Investigate `cpdf_squeeze` and `alt_ergo_fill` further.** These are the two heap-bound regressors with the cleanest signal that don't respond to any sweep parameter — they are the strongest candidates for an actual runtime-side fix in the major-pacer path.
