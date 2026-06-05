# 2026-05-16 full-suite (s, o) sweep monolith — raw logs

Per-invocation sidecar data from the 5-16 full (s, o) sweep on monolith.
See the report: [../report/2026-05-16-full-s-o-sweep-monolith.md](../report/2026-05-16-full-s-o-sweep-monolith.md).

**Contents**

- `olly_<bench>.0.0.<runtime>.<gc-params>....json` — JSONL, **one JSON object per invocation** (5 per file). Fields: `wall_time`, `cpu_time`, `gc_time`, `gc_overhead`, `max_rss_kb`, `allocations.*`, `collections.*`, `mean_latency`, `distr_latency`, `domain_stats`.
- `perf_<bench>....json` — JSONL, one per invocation. `perf stat` output: `task-clock`, `page-faults`, `cycles`, `instructions`.
- `runbms.yml` — the resolved config (post-includes, post-overrides). What was actually run.
- `runbms_args.yml` — the CLI args running-ng was invoked with.

**Run parameters**

- Host: monolith (AMD Ryzen 9 9950X, 16C/32T, governor=performance, 64 GiB, kernel 6.17)
- Compilers: `ocaml-5.4.1` vs `ocaml-d8bb46c` (5.5-beta) — base, no `-fp`/`-flambda`
- Grid: s ∈ {131072, 262144, 524288, 1048576, 2097152} × o ∈ {40, 80, 120, 150, 200} (5×5)
- 32 benchmarks × 2 runtimes × 25 cells × N=5 invocations — 8000 invocations total (1600 sidecar pairs)
- Run started 2026-05-16 03:26 (Sat)

**Note on file size**

The stdout `.log` files (per-bench environment dumps, runbms output) are
*not* mirrored here — they're ~1.3 GB and contain no analysis-relevant
data beyond what's in the JSON sidecars. They live in the original
running-ng log dir if needed: `~/running-ng/gc-sweep-logs-sweep-s-o-2026-05-16/monolith-2026-05-16-Sat-032651/`.
