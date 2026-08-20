# 2026-07-18 PR-14796 gc-pacing sweeps monolith — sidecar logs

Per-invocation sidecar data from the two 07-18 gc-pacing sweeps on monolith.
See the report: [../report/2026-07-18-pr14796-gc-pacing-sweeps-monolith.md](../report/2026-07-18-pr14796-gc-pacing-sweeps-monolith.md).

- `s-o/` — the 5×5 (s, o) sweep, 30 benches. Original: `~/running-ng-pr14796/gc-sweep-logs-pr14796-s-o-native/monolith-2026-07-18-Sat-025524/`
- `offheap-M-o/` — the 5×5 off-heap (M, o) sweep, 8 benches. Original: `~/running-ng-pr14796/gc-sweep-logs-pr14796-offheap-M-o-native/monolith-2026-07-18-Sat-174632/`

**Contents**

- `olly_<bench>.0.0.<runtime>[.<modifiers>][.<gc-params>].macro-<repo>.json` — JSONL, **one JSON object per invocation**. Fields: `wall_time`, `cpu_time`, `gc_time`, `gc_overhead`, `max_rss_kb`, `allocations.*`, `collections.*`, `mean_latency`, `distr_latency`, `domain_stats`.
- `perf_<bench>....json` — JSONL, one per invocation. `perf stat` output: `task-clock`, `page-faults`, `cycles`, `instructions`.
- `olly.ndjson` / `perf.ndjson` — the run-level contract measurement streams (one line per invocation across the whole run).
- `runbms.yml` — the resolved config (post-includes, post-overrides). What was actually run.
- `runbms_args.yml` — the CLI args running-ng was invoked with.

**Note on file size**

The stdout `.log` files (per-bench environment dumps, runbms output) are *not*
mirrored here — they contain no analysis-relevant data beyond what is in the
JSON sidecars. For the PR-14571 run they are 3.9 GB, of which ~99.9% is a
single cpdf warning line (`Warning Duplicate name/number tree key
(malformed file). Discarding.`) repeated ~22 million times. They live in the
original running-ng log dir if needed.

**Run parameters**

- Host: monolith (AMD Ryzen 9 9950X, 16C/32T, governor=performance, 64 GiB, kernel 6.17)
- Compilers: `ocaml-gc-pacing-72c712d4` vs `ocaml-trunk-e53a0322` (merge base)
- (s, o): s ∈ {131072, 262144, 524288, 1048576, 2097152} × o ∈ {40, 80, 120, 150, 200}; 30 × 2 × 25 × N=5 = 7375 invocations
- (M, o): M ∈ {11, 22, 44, 100, 250} × o ∈ {40, 80, 120, 150, 200}; 8 × 2 × 25 × N=5 = 1875 invocations
- Modifiers: `|re_par|md_par|pin_lavyek`
