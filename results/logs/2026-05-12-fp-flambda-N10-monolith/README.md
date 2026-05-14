# 2026-05-12 fp×flambda N=10 monolith — raw logs

Per-invocation sidecar data from the 5-12 N=10 monolith run. See the
report: [latest/2026-05-12-fp-flambda-5.4.1-vs-d8bb46c-monolith-N10.md](../../latest/2026-05-12-fp-flambda-5.4.1-vs-d8bb46c-monolith-N10.md).

**Contents**

- `olly_<bench>.0.0.<runtime>....json` — JSONL, **one JSON object per invocation** (10 per file). Fields: `wall_time`, `cpu_time`, `gc_time`, `gc_overhead`, `max_rss_kb`, `allocations.*`, `collections.*`, `mean_latency`, `distr_latency`, `domain_stats`.
- `perf_<bench>....json` — JSONL, one per invocation. `perf stat` output: `task-clock`, `page-faults`, `cycles`, `instructions`.
- `runbms.yml` — the resolved config (post-includes, post-overrides). What was actually run.
- `runbms_args.yml` — the CLI args running-ng was invoked with.

**Run parameters**

- Host: monolith (AMD Ryzen 9 9950X)
- Compilers: 5.4.1 vs d8bb46c (5.5-beta) × {base, -fp, -flambda, -fp-flambda} — 8 variants
- 36 benchmarks, N=10 invocations per (bench, variant) — 2880 invocations total
- Wall time of run: ~6h22m (started 2026-05-12 11:05 UTC)

**Note on file size**

The stdout `.log` files (per-bench environment dumps, runbms output) are
*not* mirrored here — they're 600MB+ and contain no analysis-relevant
data beyond what's in the JSON sidecars. They live in the original
running-ng log dir if needed: `~/running-ng/gc-sweep-logs-fp-flambda-2026-05-12/monolith-2026-05-12-Tue-110503/`.
