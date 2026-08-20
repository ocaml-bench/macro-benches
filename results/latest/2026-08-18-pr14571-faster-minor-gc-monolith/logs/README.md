# 2026-08-18 PR-14571 faster-minor-GC monolith — sidecar logs

Per-invocation sidecar data from the 08-18 full-suite run and the 08-19 `owl_gc_default` follow-up.
See the report: [../report/2026-08-18-pr14571-faster-minor-gc-monolith.md](../report/2026-08-18-pr14571-faster-minor-gc-monolith.md).

- `main/` — full-suite regression check at stock GC params, 38 benches. Original: `~/running-ng/gc-sweep-logs-pr14571/monolith-2026-08-18-Tue-044952/`
- `owl-unpinned/` — `owl_gc_default` 5×5 (s, M) grid, glibc malloc defaults
- `owl-pinned/` — same grid with `MALLOC_MMAP_THRESHOLD_=32M`, `MALLOC_TRIM_THRESHOLD_=64M`

  Both owl arms come from one running-ng run: `~/running-ng/gc-sweep-logs-pr14571-owl-s-M-malloc/monolith-2026-08-19-Wed-030433/`.
  That run emitted **four arms** (2 runtimes × pinned/unpinned) into a single directory and running-ng
  flagged the name collision (`contract.collided/`). The arms differ only by the value-less
  `malloc_mmap32m.malloc_trim64m` filename tokens, which `macrobench_loader.py` intentionally drops —
  so they are **split into two directories here**. Do not merge them: a merged load averages
  10.6 s and 13.8 s invocations into one 10-invocation cell and erases the finding.

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
**Note on filenames:** the `main/` run enabled no `macro-lavyek` benches, so it carries no
`pin_lavyek` modifier and therefore **no `re-`/`md-` tokens**. `macrobench_loader.py` in
`../notebooks/` was patched to make those two tokens optional; the upstream copies in
`~/running-ng/notebooks/` and `~/running-ng-pr14796/notebooks/` still require them and will
reject these filenames.

**Run parameters**

- Host: monolith (AMD Ryzen 9 9950X, 16C/32T, **governor=powersave**, 64 GiB, kernel 6.17)
- Compilers: `ocaml-pr14571` (`NickBarnes/ocaml` @ `16cc07f2`) vs `ocaml-trunk-3b14dfbc` (merge base)
- main: 38 benches × 2 × N=5 = 380 invocations; owl: 1 bench × 2 × 25 cells × N=5 × 2 arms = 500 invocations
