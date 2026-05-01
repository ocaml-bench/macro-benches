# macro-benches TODO

Backlog of follow-up benchmarking work. Append entries with date, owner
(if known), and enough context that someone other than the author can
pick it up.

## GC-parameter sweep on `liq_video_frames` and related — 2026-05-01

**Why.** Our cross-runtime matrix uses a single OCAMLRUNPARAM (`re-25,md-2`,
default `o`=120, default `s`) for every cell. Issue [ocaml/ocaml#13123]
showed that `o=40` recovers the 4.14-era memory footprint on the
liquidsoap workload, and our `liq_video_frames` smoke confirmed the
default `o`=120 leaves ~80 MiB of "extra" RSS the pacer doesn't need.
Running every cell with a single default risks hiding real
runtime-vs-runtime wins/losses because the optimum (`s`, `o`) almost
certainly differs across runtimes (e.g. d8bb46c's pacer change shifts
the wall vs RSS Pareto curve).

**Plan.**
1. **Parameter sweep on `liq_video_frames`** — for each runtime in the
   8-variant matrix, sweep:
   - `s` (minor heap size, default 256 Kwords = 2 MiB):
     `{128K, 256K, 512K, 1M, 2M, 4M}` words
   - `o` (space_overhead, default 120):
     `{40, 60, 80, 120, 160, 200}`
   That's 6 × 6 = 36 cells per runtime. Capture `wall_time`,
   `gc_overhead`, `max_rss_kb`, `minor` / `major` collection counts.
2. **Find the Pareto front** for each runtime (wall vs RSS). Pick:
   - The "wall-optimal" `(s, o)` for each runtime.
   - The "RSS-optimal" `(s, o)` for each runtime.
   - The "knee" of the curve.
3. **Repeat sweep on a representative subset of the suite** — at least
   one per allocation profile bucket from the README cross-table:
   `owl_gc` (off-heap small Bigarrays), `zarith_pi` (off-heap custom
   blocks), `liq_parse_typecheck` (promotion-heavy on-heap),
   `ocamlc_self_compile` (minor-heavy Ephemeron), and the existing
   `liq_video_frames` (off-heap large Bigarrays). Different optima
   across these buckets is the interesting finding — single global
   default cannot satisfy all.
4. **Re-run the 8-variant cross-runtime comparison** with each
   benchmark using its **per-runtime optimal** `(s, o)`. Compare
   against the default-parameter matrix from
   `results/2026-05-01-fp-flambda-5.4.1-vs-d8bb46c.md`. Hypothesis:
   the apparent "regressions" on `zarith_pi` (16%) and
   `ocamlc_self_compile` (10%) shrink — and the `owl_gc` "improvement"
   may shrink too. If they don't, those are real codegen / fast-path
   regressions independent of pacer tuning.

**Tooling.**
- The `gc_sweep_all_versions.yml` config in running-ng is the closest
  existing template; extend with `s` modifiers and add the
  representative-bench subset.
- olly already emits the metrics we need; no new instrumentation.
- Plot Pareto fronts with the existing `scripts/plot_*` infrastructure
  (or a new notebook).

**Status.** Not started. Filed 2026-05-01.
