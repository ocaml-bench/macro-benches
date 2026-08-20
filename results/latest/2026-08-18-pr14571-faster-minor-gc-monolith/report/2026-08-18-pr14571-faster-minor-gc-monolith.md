# PR 14571 (faster minor GC) — full suite + the `owl_gc_default` regression, explained

**Date:** 2026-08-18 (main run Tue 04:49–09:52); owl follow-up sweep 2026-08-19 (Wed 03:04–05:01)
**Host:** monolith (AMD Ryzen 9 9950X, 16C/32T, **governor=powersave**, 64 GiB, kernel 6.17)
**Compilers:** `ocaml-pr14571` (`NickBarnes/ocaml` @ `16cc07f26ded44a3c2f85ba3c0c9a032e242912f`) vs `ocaml-trunk-3b14dfbc` (`3b14dfbcca7c6c24803fc9bbbc5d4a8cc2e7f75b`, the PR's merge base)
**Harness:** running-ng v0.3.8, N=5 invocations. Main run has no `pin_lavyek` modifier set (no `macro-lavyek` benches), hence no `re-`/`md-` tokens in filenames.
**Upstream:** [ocaml/ocaml#14571](https://github.com/ocaml/ocaml/pull/14571)

| sweep | grid | benches | runtime cells | invocations |
|---|---|---|---|---|
| **main** (regression check) | — (stock GC params) | 38 | 38 × 2 = 76 | 380 |
| **owl `s` × `M`, malloc unpinned** | s ∈ {131072…2097152} × M ∈ {11, 22, 44, 88, 176} (5×5) | 1 (`owl_gc_default`) | 25 × 2 = 50 | 250 |
| **owl `s` × `M`, malloc pinned** | same grid, `MALLOC_MMAP_THRESHOLD_=32M`, `MALLOC_TRIM_THRESHOLD_=64M` | 1 | 25 × 2 = 50 | 250 |

**Configs:** [`../logs/main/runbms.yml`](../logs/main/runbms.yml), [`../logs/owl-unpinned/runbms.yml`](../logs/owl-unpinned/runbms.yml)
**Logs:** [`../logs/main/`](../logs/main/), [`../logs/owl-unpinned/`](../logs/owl-unpinned/), [`../logs/owl-pinned/`](../logs/owl-pinned/) (in-repo mirror — sidecars + YAML configs). Originals: `~/running-ng/gc-sweep-logs-pr14571/monolith-2026-08-18-Tue-044952/` and `~/running-ng/gc-sweep-logs-pr14571-owl-s-M-malloc/monolith-2026-08-19-Wed-030433/`
**Notebooks:** [`A_regression_dashboard`](../notebooks/A_regression_dashboard-executed.ipynb), [`B_runtime_behaviour`](../notebooks/B_runtime_behaviour-executed.ipynb), [`C…owl-unpinned`](../notebooks/C_gc_parameter_sweep-owl-unpinned-executed.ipynb), [`C…owl-pinned`](../notebooks/C_gc_parameter_sweep-owl-pinned-executed.ipynb)
**Dashboards:**
- `ghcr.io/udesou/ocaml-bench-dashboard:pr14571` — committed mirror at [`../dashboard/main/`](../dashboard/main/)
- `ghcr.io/udesou/ocaml-bench-dashboard:pr14571-owl-sweep` — committed mirror at [`../dashboard/owl-s-M-malloc/`](../dashboard/owl-s-M-malloc/)

```
docker run --rm -p 8080:80 ghcr.io/udesou/ocaml-bench-dashboard:pr14571
```

The mirrors are ES-module apps, so `file://` will not load them — serve the directory:
`cd ../dashboard/main && python3 -m http.server 8080`.

**All 176 cells captured with 5/5 invocations.** Allocation counters test clean (`minor_words / minor_collections` = 0.99 × s).

## TL;DR

- **The PR is a small net win across the suite and one benchmark regresses: `owl_gc_default`, +32.5% wall.** Geomean over 38 benches is **-0.54% wall, -1.36% instructions, +0.04% RSS**. Second-worst regression is `test_decompress_default` at +2.8%. So the headline is one outlier, not a pattern.
- **That `owl_gc_default` regression is not a GC regression. It is a glibc `malloc` artifact, and it disappears entirely when the malloc thresholds are pinned.** Same benchmark, same grid, `s=262144, M=44`:

  | | trunk | PR 14571 | Δ |
  |---|---|---|---|
  | wall, malloc **unpinned** | 10.7 s | 13.8 s | **+29.6%** |
  | wall, malloc **pinned** | 10.5 s | 10.6 s | **+1.1%** |
  | page-faults, unpinned | 198,541 | 9,772,876 | **+4822%** |
  | page-faults, pinned | 58,120 | 58,491 | **+0.6%** |
  | minor collections | 28,082 | 28,082 | **0.00%** |
  | major collections | 13,891 | 13,891 | **0.00%** |

  **The GC does bit-identical work in both runtimes** — minor and major collection counts match exactly. The PR changes the *order* in which blocks are freed, which pushes glibc across its `mmap`/`trim` threshold heuristic; glibc then returns memory to the kernel and immediately faults it back in, 49× more often. Pinning `MALLOC_MMAP_THRESHOLD_=32M` and `MALLOC_TRIM_THRESHOLD_=64M` removes it.
- **Across the whole 5×5 grid the story is unambiguous.** Unpinned, the PR-vs-trunk wall delta swings from **-19.1%** to **+31.6%** with no coherent shape — the signature of an allocator cliff, not a GC effect. Pinned, every one of the 25 cells lands within **±1.7%** (worst +1.73%, best -1.51%).
- **Pinning also removes a large chunk of trunk's own tuning noise.** Against its own default cell, trunk unpinned ranges -1.2% to **+42.9%**; pinned it ranges -1.3% to +1.1%. This is a measurement-hygiene finding for the whole harness, not just for this PR: any benchmark whose RSS sits near a glibc threshold will produce spurious ±30% wall deltas.
- **The real wins are in the allocation-heavy and Eio benches.** `liq_parse_typecheck_default` -4.3% (instr -4.4%), `liq_parse_typecheck_large` -4.2%, `eio_conc_default` -4.2% (instr -5.7%), `sedlex_tokenize_default` -3.5% (instr -4.8%), `eio_conc_large` -3.2%. Instruction counts move with wall time in each case.
- **RSS is essentially untouched (+0.04% geomean).** Extremes are `devkit_htmlstream_large` -6.0% and `liq_parse_typecheck_large` +7.2%.

## Recommendation

The `owl_gc_default` regression should not block this PR. It is reproducible, fully explained, and external to the runtime: identical GC work, 49× the page faults, gone when glibc's thresholds are fixed. Worth reporting on the PR with the table above so it is not re-litigated.

Separately, the harness should consider pinning `MALLOC_MMAP_THRESHOLD_`/`MALLOC_TRIM_THRESHOLD_` for all runs — the trunk-vs-trunk noise reduction (+42.9% → +1.1% worst cell) is reason enough independent of this PR.

## Caveats

- **Governor was `powersave` for both runs in this directory**, unlike the July result sets which used `performance`. Within-sweep deltas are unaffected (both arms interleave under the same governor) but absolute wall times are not comparable to the 2026-07-18 or 2026-07-24 sets.
- The owl follow-up sweep ran **four arms** (2 runtimes × malloc pinned/unpinned) into one running-ng log dir. running-ng flagged the name collision (`contract.collided/`), and the two arms are distinguished only by the value-less `malloc_mmap32m.malloc_trim64m` filename tokens — which `macrobench_loader.py` deliberately drops. **They are split here into `logs/owl-pinned/` and `logs/owl-unpinned/` so each notebook run sees exactly one arm.** Pointing the loader at a merged directory silently averages 10.6 s and 13.8 s invocations into one cell and erases the entire finding. The baked `pr14571-owl-sweep` dashboard was built from the merged directory and is subject to this; prefer the two notebooks.
