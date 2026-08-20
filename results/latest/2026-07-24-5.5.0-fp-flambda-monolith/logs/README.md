# 2026-07-24 5.5.0 fp/flambda monolith — sidecar logs

Per-invocation sidecar data from the 07-24 `-fp`/`-flambda` sweep on monolith.
See the report: [../report/2026-07-24-5.5.0-fp-flambda-monolith.md](../report/2026-07-24-5.5.0-fp-flambda-monolith.md).

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
Original: `~/running-ng/gc-sweep-logs-5.5.0-fp-flambda-2026-07-24/monolith-2026-07-24-Fri-015106/`

**Run parameters**

- Host: monolith (AMD Ryzen 9 9950X, 16C/32T, governor=performance, 64 GiB, kernel 6.17)
- Compilers: `ocaml-5.5.0` built stock / `--enable-frame-pointers` / `--enable-flambda` / both
- 31 benchmarks × 4 variants × N=5 — 620 invocations (124 cells, 248 sidecar pairs)
- Run started 2026-07-24 01:51 (Fri)

⚠️ **Allocation counters here are ~8× inflated** — OCaml 5.5.0 `Runtime_events` emits
`EV_C_MINOR_ALLOCATED_WORDS` in bytes, not words (measured `minor_words/minor_collections`
= 7.86 × s). Wall, RSS, `gc_overhead`, latency and `perf` counters are unaffected.
