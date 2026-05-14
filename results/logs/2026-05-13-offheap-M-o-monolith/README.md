# 2026-05-13 (M, o) off-heap sweep monolith — raw logs

Per-invocation sidecar data from the 5-13 (M, o) sweep, the off-heap half
of the 2-sweep overnight run. Report: [latest/2026-05-13-regression-and-offheap-sweeps-monolith.md](../../latest/2026-05-13-regression-and-offheap-sweeps-monolith.md).

**Contents**

- `olly_<bench>.0.0.<runtime>.perf_grp1.re-25.md-2.M-<M>.o-<o>.macro-*.json`
  — JSONL, 3 invocations per file. Fields as documented for 5-12.
  The `.M-X.o-Y.` segment encodes the (M, o) cell.
- `perf_<bench>....json` — perf stat sidecar.
- `runbms.yml`, `runbms_args.yml` — resolved config + CLI args.

**Sweep grid**

- 12 benchmarks (off-heap subset — includes all 5 `liq_video_frames_*` variants)
- 2 runtimes: `ocaml-5.4.1` vs `ocaml-d8bb46c` (base only)
- `M ∈ {11, 22, 44, 100, 250}` × `o ∈ {40, 80, 120, 150, 200}` — 5×5 = 25 cells
- N=3 invocations per cell — 1800 invocations total
- Default cell (`M=44, o=120`) is in the grid

**Run window**

- Host: monolith
- Wall time: ~3h28m (started 2026-05-13 14:29 UTC)
- All cells captured cleanly at N=3.

**The `_pool` variant**

`liq_video_frames_pool` (POOL=1, refcounted-pool stub) is in this sweep —
the synthetic [ocaml/ocaml#14533](https://github.com/ocaml/ocaml/issues/14533)
reproducer. See report §Sweep B for the intra-d8b vs cross-version
comparison.
