# macro-benches TODO

Backlog of follow-up benchmarking work. Append entries with date, owner
(if known), and enough context that someone other than the author can
pick it up.

## Close runtime-feature coverage gaps — 2026-05-15 (Fri)

**Why.** A source-grounded audit of all 32 benchmark programs against
the OCaml runtime mechanisms each one exercises on the hot path (see
README §"Runtime-feature coverage matrix") and against the `tags:`
block in [running-ng macro_base.yml](https://github.com/udesou/running-ng/blob/adding-ocaml-support/src/running/config/base/ocaml/macro_base.yml)
turned up **10 runtime mechanisms that no benchmark exercises hot**.
A regression in any of these would slip through the entire suite
silently. This entry collects them so we can prioritise closures.

The two named `gap:` tags in `macro_base.yml`
(`RUNNING_TAG=ephemerons` and `RUNNING_TAG=kcas`) already error
loudly when invoked, which keeps these specific gaps discoverable —
but the rest are documented only in the README and aren't first-class
in the running-ng surface.

**The 10 gaps, in rough order of importance.**

| # | Tag / mechanism                                  | Evidence of absence                                                                                                                                                                                                                                                                          | Candidate closures                                                                                                                                                                                                                                                                                                                 |
|---|--------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 | **`Ephemeron.K1 / K2 / Kn`**                     | `grep -rn Ephemeron typing/ bytecomp/ driver/ utils/` in OCaml 5.4.1 *and* trunk compiler-libs returns nothing; `btype.ml:46` uses `Hashtbl.Make`. Merlin's `saved_parts.ml:3` does have one `Ephemeron.K1`, but it's touched only at parse time (small N) and `merlin_bench` is also currently disabled. Coq's `clib/cEphemeron.ml` is only reached by the VM backend, which `coq_corelib_stress.v` doesn't hit. | Find an ephemeron-heavy real workload (e.g. coq with `Native_compute` enabled hits the VM and CEphemeron — but that's a different shape than kernel reduction). Alternatively: small dedicated benchmark wrapping `Ephemeron.K1.Hashtbl` (sandmark-style microbench, but DaCapo-scaled). Could be 100–200 lines. |
| 2 | **kcas / lock-free MCAS**                        | Lavyek imports `kcas` + `kcas_data` in `dune-project` but `grep -rn 'Kcas\.\|Kcas_data\.\|Loc\.' duniverse/lavyek/src/` returns nothing (REMOVED.md:22 documents historical removal). Lavyek's in-memory index is hand-rolled `Atomic.compare_and_set`. | Standalone benchmark wrapping `Kcas_data.Hashtbl` or `Kcas_data.Queue` under contention from N domains. Doc-flavoured: ~150 lines. Could vendor as a sibling to lavyek. |
| 3 | **Domainslib work-stealing pools**               | No benchmark uses `Domainslib.Task.run` / parallel_for. Lavyek dispatches via a manual `Atomic.fetch_and_add` chunk counter, not work-stealing.                                                                                                                                              | Sandmark Phase 2 imports — `parallel_binarytrees`, `raytracer`. See existing TODO entry "N>2 domain stress benchmark — possibly via `infer`" for the broader N-domain stress shape; Domainslib is a subset of that work.                                                                                                       |
| 4 | **Forced `Gc.compact` / `Gc.full_major`**        | `grep -rn 'Gc\.compact\|Gc\.full_major' benchmarks/` returns nothing in any driver. `Eio/bench/` has `Gc.full_major` but only outside any benchmark's hot loop.                                                                                                                              | Driver that forces `Gc.compact` mid-workload (e.g. every 100 iterations of an existing allocation-heavy bench like `liq_parse_typecheck`). Cheap to add: a new "_compact" variant that wraps the existing driver. Compaction-interaction-with-finalisers is the interesting story for `owl_gc` and `liq_video_frames_pool`. |
| 5 | **`Gc.alarm` / `Gc.create_alarm` callbacks**     | `grep -rn 'Gc\.alarm\|Gc\.create_alarm' benchmarks/ duniverse/ vendor/` returns nothing.                                                                                                                                                                                                     | Synthetic: an alarm callback that runs a small `Hashtbl.replace`-style mutation every cycle. Tiny benchmark (~50 lines). Closes the alarm-machinery gap.                                                                                                                                                                          |
| 6 | **High-frequency `Sys.set_signal` delivery**     | Alt-ergo registers SIGINT/SIGVTALRM/SIGPROF (`signals_profiling.ml:32-89`) but the timer fires at most once per long solve. No benchmark exercises rapid (e.g. ≥100/s) signal delivery in a tight allocator loop.                                                                            | Synthetic: an `itimer`-driven SIGALRM at 1 ms with an OCaml handler that does trivial work. Combine with an existing allocator-heavy driver (`coqc`, `liq_parse_typecheck`) for the signals-during-alloc interaction.                                                                                                                |
| 7 | **Pure-OCaml hot inner-loop float (flambda)**    | `owl_gc` defers `Mat.dot` to OpenBLAS — flambda has nothing to optimise in the inner loop. No `Array.iter` numerical kernel exists in the suite.                                                                                                                                             | Sandmark imports: `nbody`, `raytracer`, `mandelbrot`. Each is ~200 lines pure OCaml. Picks one — `nbody` is the canonical flambda-sensitive one (Bonzini et al.).                                                                                                                                                                  |
| 8 | **`Bigarray` slicing / reshape patterns**        | `owl_gc` creates and uses Array2 but never calls `Genarray.slice_left` / `reshape` in a hot loop. `liq_video_frames_pool` fills planes without slicing.                                                                                                                                      | New `Bigarray.Array1.sub` / `Genarray.slice_left` micro-stressor, or fork `owl_gc` to use slice-based access instead of `{i,j}` indexing.                                                                                                                                                                                          |
| 9 | **Polling-points / safe-point density**          | No benchmark stresses cooperative-cancellation. OxCaml's `--enable-poll-insertion` mode adds polls but no benchmark drives them at saturation.                                                                                                                                                | Synthetic: tight `for i = 0 to N do ... done` loop with no allocation, in an `Eio.Switch` with periodic cancellation pokes. Tests both poll insertion frequency and cancellation latency. ~100 lines.                                                                                                                                |
| 10 | **Direct user `Effect.Deep.try_with` outside Eio** | Every `Effect.perform` in the suite flows through Eio's deep handlers. A bug specific to a user-defined `Effect.Deep` `try_with` outside the Eio runtime would slip through.                                                                                                                  | Sandmark `effects` microbench or a small adaptation: define a couple of user effects (`Read`, `Write`, `Yield`) and bounce them under a custom handler. ~80 lines.                                                                                                                                                                  |

**Cross-references.**
- The existing TODO entry "N>2 domain stress benchmark — possibly via
  `infer`" (filed 2026-05-01) covers gap #3 (work-stealing) and partly
  gap #10 (effects via Eio at high parallelism). Bundle when picking up.
- The existing TODO entry "Investigate `merlin` as a domains-using
  benchmark" (filed 2026-05-04) — re-enabling `merlin_bench` would
  partly soften gap #1 (Ephemerons cold via `saved_parts.ml`), but
  Saved_parts is light traffic, so it doesn't fully close it.
- Gaps #1, #2, #5, #7, #8, #9, #10 are candidates for **Sandmark
  imports** (mostly small, already-written microbenchmarks adapted to
  DaCapo timing).
- Gaps #4, #6 are **cheap synthetic drivers** (~50–100 lines each)
  that can be added without vendoring an external tool.

**Suggested order of attack (cheapest signal first).**

1. Synthetic `Gc.alarm` driver (gap #5) — tiny, closes a discrete
   runtime API.
2. Synthetic `Gc.compact`-during-workload variant of an existing
   bench (gap #4) — wraps `liq_parse_typecheck` or `owl_gc`.
3. Sandmark `nbody` import for flambda (gap #7) — the user has
   asked about this before in flambda-result discussions; it
   directly addresses a known suite-wide weakness.
4. Synthetic ephemeron stress (gap #1) — small benchmark wrapping
   `Ephemeron.K1.Hashtbl`. Two-deep: also gives us an "expected
   regression direction" baseline if `caml_ephe_*` ever changes.
5. Synthetic kcas stress (gap #2) — sibling to lavyek; uses
   `Kcas_data.Hashtbl` from the already-vendored dep.
6. Sandmark `parallel_binarytrees` import (gap #3) — feeds into the
   existing N-domain stress TODO.

**Status.** Not started. Filed 2026-05-15 after source-grounded
classification of all 32 benchmarks (see commit
[`343299d` in macro-benches](https://github.com/ocaml-bench/macro-benches/commit/343299d)
and [`7826144` in running-ng](https://github.com/udesou/running-ng/commit/7826144)).
The 10 gaps above are what's missing once those classifications are
in place — closing any of them takes the suite from "would silently
miss this regression class" to "would catch it".


## Investigate `ocamlc_self_compile` allocation regression on d8b — 2026-05-06 (Wed)

**Why.** `ocamlc_self_compile` regresses ~+8% wall on d8b across all flag
combos but only drops −5% RSS, while sibling RSS-winners (`cpdf_*`,
`menhir_sysver`) drop 20-40% RSS for a similar wall cost. Looking at
olly stats from the 2026-05-03 monolith N=3 run, the cause looks
qualitatively different from the pacer-trade story we see elsewhere:

| metric (5.4 → d8b)       | 5.4      | d8b      | Δ        |
|---|---|---|---|
| total alloc (minor heap) | 8.57 GB  | 9.90 GB  | **+15.5%** |
| minor collections        | 4384     | 5066     | +15.6%   |
| major collections        | 16       | 12       | −25%     |
| promoted bytes           | 1093 MB  | 1133 MB  | +3.6%    |
| max_rss                  | 1017 MiB | 967 MiB  | −4.9%    |

Same input (`compile_workload.ml`, 400k lines, deterministic),
different runtimes — d8b allocates 1.3 GB more for the same compile.
This is the workload itself (ocamlc + the compiler-libs / stdlib it
links against) allocating differently between versions, not the
pacer collecting more aggressively. By contrast `cpdf_merge`'s total
allocation is exactly identical across versions (2.08 GB both) and
only RSS moves — that's the canonical pacer story. RSS doesn't drop
much here because the live set (parsetree forest + ephemeron tables
the typer holds until compile finishes) is roughly the same in both
versions; the pacer has nothing to shrink below that floor.

**Hypotheses.**
- ~~`typing/btype.ml` ephemeron-backed type hash-consing — canonical
  real-world ephemeron workload in this bench; cache table size or
  bucket policy may have shifted.~~  **Invalidated 2026-05-15** during
  source-grounded coverage-matrix work (see commit `343299d`).
  `grep -rn Ephemeron typing/ bytecomp/ driver/ utils/` returns
  nothing in OCaml 5.4.1 *and* trunk compiler-libs — `btype.ml:46`
  uses `Hashtbl.Make`, not `Ephemeron`. The original hypothesis was
  inherited from an earlier README claim that didn't survive
  verification.
- **Stdlib growth** (now the leading hypothesis) — d8b's stdlib has
  more modules/types than 5.4, so ocamlc has to typecheck more
  external type info per compile.
- **`Hashtbl` resize policy** or per-entry allocation overhead in
  `TypeHash` (`btype.ml:46 Hashtbl.Make`) — the actual table backing
  type hash-consing. This is what we previously mis-identified as
  ephemeron-backed; it remains a real suspect under its corrected
  identity.
- **`Marshal`** — `.cmi` writing via `file_formats/cmi_format.ml:87`
  *and* `.cmo` writing via `bytecomp/emitcode.ml:33`; serialisation
  buffer behaviour may have changed (especially `Compression.*`
  introduced in 5.x).
- **`Bigarray.Array1` emit buffer** in `bytecomp/emitcode.ml:53` —
  growth via `Bigarray.Array1.blit`/`sub`; per-blit cost or growth
  policy may have shifted.

**Next steps when picking this up.**
1. Run with `OCAMLRUNPARAM=v=0x400` and inspect the per-cycle GC log
   to see *when* during the compile the extra allocation lands
   (parse vs typecheck vs marshal). That alone narrows the source.
2. Reduce `compile_workload.ml` to one module (1/30th the input)
   and re-measure. If the +15% scales linearly it's per-AST-node;
   if it stays a fixed offset it's startup / stdlib loading.
3. If still ambiguous, statmemprof a single invocation under each
   version and diff the source-location attribution.
4. Once narrowed, bisect the 5.4 → d8b range to find the commit that
   introduced the allocation increase. Likely candidates: touches
   in `typing/`, `utils/`, or stdlib additions.

**Status.** Not started. Filed 2026-05-06. Surfaced while preparing
the fp×flambda meeting summary; not blocking that meeting.


## Domainslib / work-stealing N-domain benchmark — 2026-05-04 (Mon)

**Why.** The suite's domain-coverage situation changed significantly
since this entry was first filed.  **Lavyek (`lavyek_kv_{1,2,4,8}d`)
now provides** N>2 domain shared-heap GC under contention, real CAS/
fence traffic via `Atomic.compare_and_set` on memtable buckets, and
io_uring on the hot path (~2026-05-01 vendoring).  Merlin-domains
landed as `merlin_bench` (currently disabled — upstream race).

What lavyek does **not** cover, and remains a gap:

- **Domainslib-style work-stealing scheduler load.**  Lavyek dispatches
  work via a manual `Atomic.fetch_and_add` chunk counter, not a
  work-stealing pool.  `grep -rn Domainslib duniverse/ benchmarks/`
  returns nothing in the suite — there's no consumer of
  `Domainslib.Task.{run,parallel_for,async}`.
- **kcas / lock-free MCAS.**  Lavyek's `dune-project` lists `kcas` +
  `kcas_data` but `grep` confirms the source doesn't actually call
  them — see the new "Close runtime-feature coverage gaps" entry at
  the top of this file for the full evidence.

**Options for closing the work-stealing gap.**

1. **Sandmark `parallel_binarytrees` import** (preferred).  Already a
   Domainslib workload; ~200 lines once adapted to DaCapo timing
   conventions.  Established result shape, comparable to lavyek for
   N-domain scaling but on a completely different workload axis.
2. **Synthetic work-stealing benchmark.**  A tree-of-tasks driver
   under `Domainslib.Task` (~150 lines) — minimal but enough to
   exercise the scheduler.
3. **Meta's `infer` static analyzer** (original idea).  Uses domains
   internally for parallel analysis.  Likely the largest of the three
   — vendoring cost remains the main open question.  See the open
   questions below for what to verify before committing to this path.

**Open questions for option 3 (`infer`).**
- Is `infer` opam-installable / dune-buildable from the OCaml side?
  (Last check it had a Java/SBT-driven build for parts of it.  The
  actual analyzer cores are OCaml.)
- What's the work-distribution pattern — `Domainslib.Task.parallel_for`,
  hand-rolled pool, or something else?
- Compare vendoring cost: real infer (full deps) vs sandmark import
  (option 1) vs synthetic (option 2).

**Status.** Filed 2026-05-01.  **Updated 2026-05-15** to reflect
lavyek's landing (closes N>2 shared-heap GC + CAS traffic) and to
narrow the remaining gap to specifically **work-stealing scheduler
load**.  Sandmark `parallel_binarytrees` import is now the cheapest
path; `infer` remains an option but no longer the only one.


## Re-enable `merlin_bench` once upstream race is fixed — 2026-05-04 (Mon)

**Why.** When this entry was first filed, the question was "should we
vendor merlin's domains branch as a benchmark?" — that question is
**resolved**: `merlin_bench` is vendored from the merlin-domains
branch (PR [#1890](https://github.com/ocaml/merlin/pull/1890)) and
wired into the suite at `benchmarks/merlin/`.  It's the only 2-domain
steady-state workload we have (main + typer worker; complements
lavyek which is N≥2 worker-pool).

The bench is **currently disabled** because the merlin-domains
typer-domain handoff has a non-deterministic race that fires
`Types.rev_log → Invalid -> assert false` at N≥2 iterations on
**both** 5.4.1 and d8bb46c/5.5-beta.  Full repro is documented in
[`benchmarks/merlin/UPSTREAM_BUG.md`](benchmarks/merlin/UPSTREAM_BUG.md).
The suite entry in
`running-ng/.../macrobenchmarks_base.yml` is set to `[]` (empty
programs); source is kept in tree.

**Next steps when picking this up.**
1. Watch merlin PR #1890 / merlin-domains branch for the race fix.
2. Once fixed: re-vendor the typer source, flip `macro-merlin: []`
   back to `- merlin_bench` in `macro_base.yml`, run the suite, and
   check the assertion no longer fires across all matrix runtimes.
3. Re-validate the workload: the 7 cram-bench queries, ~16s wall
   at arg=4, ~1 GB RSS, gc_overhead ~24%.  See README §
   "merlin_bench" for the expected profile.

**Side effect on coverage matrix.**  Re-enabling merlin_bench
upgrades several tag entries in `running-ng/.../macro_base.yml`'s
`tags:` block: `domains`, `effects`, `atomics` all get `merlin_bench`
moved from `cold:` to `exercised_by:`; `ephemerons` cold list keeps
merlin (Saved_parts is small even when enabled).

**Status.** Filed 2026-05-01, vendored 2026-05-01-ish, disabled
2026-05-04 due to upstream race.  **Waiting on upstream fix** to
re-enable.  Periodically re-check #1890 status.


## GC-parameter sweep on `liq_video_frames_pool` and related — 2026-05-01

**Why.** Our cross-runtime matrix uses a single OCAMLRUNPARAM (`re-25,md-2`,
default `o`=120, default `s`) for every cell. Issue [ocaml/ocaml#13123]
showed that `o=40` recovers the 4.14-era memory footprint on the
liquidsoap workload, and our `liq_video_frames_pool` smoke confirmed the
default `o`=120 leaves ~80 MiB of "extra" RSS the pacer doesn't need.
Running every cell with a single default risks hiding real
runtime-vs-runtime wins/losses because the optimum (`s`, `o`) almost
certainly differs across runtimes (e.g. d8bb46c's pacer change shifts
the wall vs RSS Pareto curve).

**Plan.**
1. ✅ **Parameter sweep on `liq_video_frames_pool`** — done across
   multiple revisions of the experiment configs (the
   `offheap_M_o_sweep_*.yml` series in
   `running-ng/src/running/config/experiments/`).
2. ✅ **Find the Pareto front** for `liq_video_frames_pool`.
   **Headline finding (resolved 2026-05-14):** `M=250` trades **+10%
   RSS for −17% CPU** on the real liquidsoap pipeline on Ryzen 9
   9950X — the predicted #14533 "free lunch" shape materialises in
   the large-`M` regime.  Full repro + numbers in the
   `offheap_M_o_sweep_2026_05_13.yml` results dump.
3. **Repeat sweep on a representative subset of the suite** —
   still **partially done**.  Need to extend to one bench per
   allocation profile bucket from the README cross-table:
   - `owl_gc` (off-heap small Bigarrays) — *pending*
   - `zarith_pi` (off-heap custom blocks) — *pending*
   - `liq_parse_typecheck` (promotion-heavy on-heap) — *pending*
   - ~~`ocamlc_self_compile` (minor-heavy Ephemeron)~~ —
     **mis-classified**; updated 2026-05-15 (see commit `343299d`)
     to "minor-heavy Hashtbl + Marshal + Bigarray emit buffer"
     after source-grounded matrix work.  Still a worthwhile
     subject for the sweep, just under its corrected character.
   - `liq_video_frames_pool` — ✅ done (see above)
4. **Re-run the 8-variant cross-runtime comparison** with each
   benchmark using its **per-runtime optimal** `(s, o)`. Compare
   against the default-parameter matrix from
   `results/2026-05-01-fp-flambda-5.4.1-vs-d8bb46c.md`. Hypothesis:
   the apparent "regressions" on `zarith_pi` (16%) and
   `ocamlc_self_compile` (10%) shrink — and the `owl_gc` "improvement"
   may shrink too. If they don't, those are real codegen / fast-path
   regressions independent of pacer tuning.  **Status: pending step 3
   completion.**

**Tooling.**
- The `gc_sweep_all_versions.yml` and `offheap_M_o_sweep_*.yml`
  configs in running-ng are the working templates; extend with `s`
  modifiers and add the representative-bench subset.
- olly already emits the metrics we need; no new instrumentation.
- Plot Pareto fronts with the existing `scripts/plot_*` infrastructure
  (or a new notebook).  Notebook C (GC parameter sweep) in running-ng
  (commit `c1b0351`) is the closest existing analysis surface.

**Status.** Filed 2026-05-01.  **Step 1+2 resolved for
`liq_video_frames_pool` 2026-05-14** (M=250 free-lunch shape
confirmed: +10% RSS / −17% CPU on real workload).  Steps 3+4 still
pending for the representative-bench subset across allocation-profile
buckets.
