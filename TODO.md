# macro-benches TODO

Backlog of follow-up benchmarking work. Append entries with date, owner
(if known), and enough context that someone other than the author can
pick it up.

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
- `typing/btype.ml` ephemeron-backed type hash-consing — canonical
  real-world ephemeron workload in this bench; cache table size or
  bucket policy may have shifted.
- Stdlib growth — d8b's stdlib has more modules/types than 5.4, so
  ocamlc has to typecheck more external type info per compile.
- `Marshal` — `.cmi` writing at end of compilation; serialisation
  buffer behaviour may have changed.
- Hashtbl resize policy or per-entry allocation overhead.

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


## N>2 domain stress benchmark — possibly via `infer` — 2026-05-04 (Mon)

**Why.** Once merlin-domains is in (covers main + 1 typer domain),
the suite still won't have anything that exercises:
- N>2 domain shared-heap GC under contention
- Work-stealing scheduler load (Domainslib)
- Many-domain CAS / fence storms

These were originally going to be filled by Sandmark Phase 2 imports
(`parallel_binarytrees`, `raytracer`). User has a separate idea
involving Meta's `infer` static analyzer, which uses domains
internally for parallel analysis.

**Open questions for picking this up.**
- Is `infer` opam-installable / dune-buildable from the OCaml side?
  (Last check it had a Java/SBT-driven build for parts of it. The
   actual analyzer cores are OCaml.)
- If too heavy: build a **synthetic benchmark that mimics infer's
  domain-pattern**. Need to know what that pattern is — likely a
  work-stealing pool fed function summaries, with a shared index of
  results.
- Compare cost: vendoring real infer (full deps) vs writing the
  synthetic (~200 lines).

**Status.** Filed 2026-05-01, parked behind merlin-domains.


## Investigate `merlin` as a domains-using benchmark — 2026-05-04 (Mon)

**Why.** Supervisor suggested merlin as an example of a benchmark that
uses domains for typechecking — IDE servicing requests in parallel via
multiple typer domains. If real, it would be the first benchmark in
the suite that genuinely exercises OCaml 5's domain machinery (current
suite has `eio_fiber_stream` for fiber scheduling but nothing that
exercises shared-heap / cross-domain GC).

**What we know so far (initial scan, 2026-05-01).**
- Merlin's `main` branch has **no** `Domain.spawn` / `Domainslib` /
  `Atomic.` / `Mutex.` references — the released merlin is single-
  threaded.
- There is an active multi-PR effort to add domains:
  - **#1890 "Typer domain"** — open PR, base `main`. The headline
    work for this feature.
  - **#1959 / #1958 "Merlin domains Rebased"** — closed (presumably
    superseded).
  - **#1920 "Introduce typer interruption"** — closed.
  - **#1908 / #1909 "Upstream lyrm in merlin domains"** — closed.
- Naming pattern (`merlin-domains` branch) suggests Tarides /
  upstream-merlin team are working on this. Worth asking the
  supervisor who's driving it and whether there's a stable branch
  intended for downstream consumption yet.

**Next steps when picking this up.**
1. Read the current state of #1890 — is it close to merging? Is there
   a downstream-consumable branch / fork? What's the workload shape
   of the typechecking parallelism (one domain per request, or per
   file, or work-stealing pool)?
2. Check if there's a reproducible benchmark script in the PR or
   linked from it. Look at #1967 ("Some bench using `cram` and
   `time`") — that's a sibling closed PR that might have benchmark
   harness work.
3. If yes to a stable branch + benchmark workload → vendor it like
   other benchmarks (see README §"Adding a new benchmark"). The
   workload would probably be: load a project, fire N typecheck
   requests across M domains, measure throughput + RSS + GC stats.
4. If no stable branch yet → add a placeholder note in the README
   coverage gaps section, revisit when upstream lands.

**Open questions for supervisor.**
- Is there a specific branch / fork they have in mind?
- Are they expecting us to use the stock merlin protocol, or run
  the typer with a synthetic driver?
- What's the comparison they care about — same-runtime
  domain-count scaling, or domains-on vs domains-off?

**Status.** Filed 2026-05-01, scheduled to dig in 2026-05-04 (Mon).


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
