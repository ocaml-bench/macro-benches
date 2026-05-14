# 2026-05-13 (s, o) regression sweep monolith — raw logs

Per-invocation sidecar data from the 5-13 (s, o) sweep, the regression-targeted
half of the 2-sweep overnight run. Report: [latest/2026-05-13-regression-and-offheap-sweeps-monolith.md](../../latest/2026-05-13-regression-and-offheap-sweeps-monolith.md).

**Contents**

- `olly_<bench>.0.0.<runtime>.perf_grp1.re-25.md-2.s-<s>.o-<o>.macro-*.json`
  — JSONL, 3 invocations per file (N=3). Fields as documented for 5-12.
  The `.s-X.o-Y.` segment encodes the (s, o) cell.
- `perf_<bench>....json` — perf stat sidecar.
- `runbms.yml`, `runbms_args.yml` — resolved config + CLI args.

**Sweep grid**

- 16 benchmarks (the regressed set from the 5-12 N=10 run)
- 2 runtimes: `ocaml-5.4.1` vs `ocaml-d8bb46c` (base only — no fp/flambda)
- `s ∈ {131072, 262144, 524288, 1048576, 2097152}` × `o ∈ {40, 80, 120, 150, 200}` — 5×5 = 25 cells
- N=3 invocations per cell — 2400 invocations total
- Default cell (`s=262144, o=120`) is in the grid

**Run window**

- Host: monolith
- Wall time: ~4h23m (started 2026-05-13 09:52 UTC)
- All cells captured cleanly at N=3 — no missing data.
