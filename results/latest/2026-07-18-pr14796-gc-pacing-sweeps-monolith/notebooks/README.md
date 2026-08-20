# running-ng notebooks

Jupyter-based analysis of benchmark runs produced by running-ng. Two
notebooks, two audiences, one shared loader.

## 1. Purpose and scope

These notebooks are a **prototyping analysis layer** on top of running-ng's
log and sidecar output. They are not the final visualisation surface for
the OCaml benchmarking project — that is a later-phase concern (web
dashboard, likely Vega-Lite-driven, implemented in OCaml). The purpose of
the notebooks is to let a researcher iterate quickly on *what questions
to ask* and *how to answer them* while the benchmark format and
methodology are still being worked out.

Two concrete goals:

1. Answer "did this compiler change make things faster or slower?"
   without leaving a notebook.
2. Produce charts and tables suitable for a report or paper figure,
   reproducibly, from a single cached dataset.

Everything below is designed so that the data contracts survive a later
re-implementation in OCaml. The filename scheme, JSON sidecar shape, and
the set of derived metrics are documented so a re-implementer can stay
compatible without reading Python.

## 2. Audience and notebook map

Two reader profiles:

- **Regression reviewer** — runtime developer, release engineer, or
  reviewer asking *"did this get better or worse?"* Reads **Notebook A**.
  Cares about ratios vs. baseline, ranked regressions, pass/warn
  verdicts. Does not want raw sub-second timings.
- **Runtime researcher** — GC or compiler researcher asking *"what is
  the system actually doing?"* Reads **Notebook B**. Cares about
  absolute values, distribution shapes (multi-modality signals a
  measurement problem), allocation and collection counts, hardware
  counters.

| Notebook | File | Primary metric layer | Style |
|---|---|---|---|
| A — Regression Dashboard | `A_regression_dashboard.ipynb` | Layer 1 + instruction-count headline | matplotlib only, heavily commented, ratios-first |
| B — Runtime Behaviour Explorer | `B_runtime_behaviour.ipynb` | All three layers, absolute values | seaborn allowed (violin / ECDF) |
| C — GC Parameter Sweep | `C_gc_parameter_sweep.ipynb` | Wall time + max RSS over the swept axes | matplotlib heatmaps + Pareto scatter; axis-agnostic (detects which of `{s, o, M, m, ...}` actually vary) |

A populates the parquet cache at `cache/macrobench.parquet`. B reads
from that cache. Run A first.

## 3. Terminology

These terms come from the broader OCaml benchmarking proposal and are
used consistently across the notebooks, the loader, and this README.

- **Configuration.** A tuple of (compiler version × compiler options ×
  GC parameters) that fully specifies the environment a benchmark is
  run in.
- **Invocation.** A single execution of a benchmark binary under a
  configuration.
- **Measurement.** The metric values captured for one invocation —
  wall time, instruction count, GC statistics, and so on.
- **Baseline.** A stored set of measurements under a canonical
  configuration, used as the reference point for comparison.
- **Regression.** A *statistically significant* slowdown relative to
  the baseline. See §9 for why "statistically significant" does not
  yet apply to the current dataset.
- **Profile.** A named selection of benchmarks and configurations run
  together — e.g. `ci-fast`, `gc-sweep`, `baseline-comparison`.

**"Variant" as shorthand.** In this dataset the GC parameters are fixed
(re-23, md-2), so what varies across rows is the compiler half of the
configuration: version + options. The code and notebooks call this
`variant` (`"5.4.1/baseline"`, `"d8bb46c/flambda"`, etc.) because it is
shorter than `configuration` and there is no ambiguity. When a future
dataset varies GC parameters, the same column should be renamed.

## 4. Architecture: why this lives in running-ng

These notebooks could in principle be a separate repository. They are
not, for now, because the coupling between the viz layer and the
orchestrator is real and heavy:

- Filename scheme, JSON sidecar schemas, and the sidecar discovery
  rules are all running-ng concerns.
- `running.analysis.json_sidecars` is imported by both the notebooks
  and `scripts/plot_gc_sweep.py` — one source, no duplication.
- A schema change in running-ng (new olly field, new perf group) can
  be shipped atomically with the notebook consumer. Two repos would
  turn one PR into two coordinated PRs.
- Release cadence matches: the notebooks evolve as the benchmarking
  questions evolve.

**Criteria for splitting later.** Any of:

- A third party wants to consume the same sidecar schema without
  running-ng in the loop.
- A non-Python UI emerges (for example an OCaml Ocsigen dashboard) that
  reads the same outputs.
- Release cadence genuinely diverges — viz iterating weekly while
  running-ng is stable.
- Non-overlapping contributor sets on one side but not the other.

None of those are true today. If they become true, moving `notebooks/`
and `src/running/analysis/` into a new repository is a day's work.

## 5. Data contract

This section is the most important part of the README for anyone
re-implementing the pipeline in another language.

### 5.1 Log directory layout

A benchmark run produces a single directory containing three kinds of
files per (benchmark × configuration × invocation):

- `<name>.log` — plain text. Command, environment snapshot, stdout.
- `olly_<name>.json` — NDJSON sidecar from
  [`runtime_events_tools`](https://github.com/tarides/runtime_events_tools).
- `perf_<name>.json` — NDJSON sidecar from `perf stat --json`.

Each non-empty line in a sidecar corresponds to one invocation of the
benchmark, in execution order. With N invocations configured in the
runbms YAML, each sidecar has N lines. The loader emits **one
DataFrame row per invocation**, with an `invocation_idx` column
running 0..N−1 inside each (benchmark, configuration) cell. When the
two sidecars disagree on line count, the smaller count wins so that
rows stay aligned.

A legacy single-sidecar format (`<name>.json` with both olly and perf
as a top-level object) is still supported for backward compatibility;
it is treated as a single invocation.

### 5.2 Filename scheme

```
<benchmark>.<iter>.<sub_iter>.ocaml-<version>[-<flags>].perf_grp<N>.re-<R>.md-<M>[.<gc_key>-<gc_val>]*[.macro-<repo>].log
```

Field by field:

| Field | Type | Example | Meaning |
|---|---|---|---|
| `benchmark` | lowercase `[a-z0-9_]+` | `alt_ergo_fill` | Benchmark name |
| `iter`, `sub_iter` | int | `0.0` | Run-level repetition indices. *Not* the invocation axis — invocations come from the sidecar NDJSON lines |
| `version` | release tag, git SHA, branch name | `5.4.1`, `d8bb46c`, `trunk` | OCaml compiler version. The loader accepts anything `runbms` produces here |
| `flags` | one of `fp`, `flambda`, `fp-flambda` or absent | `flambda` | Compiler options. Absent → `"baseline"` in the loader |
| `perf_grp<N>` | int | `perf_grp1` | Which pre-defined perf counter group was collected |
| `re-<R>` | int | `re-23` | runtime_events ring size |
| `md-<M>` | int | `md-2` | maximum number of domains |
| `<gc_key>-<gc_val>` | int, zero or more, any order | `s-262144.o-120.M-11.m-100` | GC sweep parameters. Known keys land in dedicated columns (`s` minor heap, `o` space overhead, `M`, `m`); unknown keys land in `gc_params_extra` as a dict |
| `macro-<repo>` | lowercase with hyphens, optional | `macro-alt-ergo-monorepo` | Source repository of the macro-benchmark. Absent for micro-benchmarks |

GC sweep tokens are **order-agnostic**: `runbms` may emit them in any
sequence between `md-<M>` and `.macro-<repo>` (or `.log`). The loader
splits the token soup with a secondary regex (`GC_PARAM_RE` in
`macrobench_loader.py`); to add a new dedicated column, append the key
to `KNOWN_GC_PARAMS`. The loader at `notebooks/macrobench_loader.py`
implements this scheme in one header regex plus the GC-param helper. A
re-implementer should copy those plus `_split_ocaml`.

### 5.3 Olly sidecar schema

NDJSON. Each line is an independent invocation record. Fields the
loader consumes:

```json
{
  "version": 1,
  "wall_time": 0.16,
  "cpu_time":  0.16,
  "gc_time":   0.07,
  "gc_overhead": 42.81,
  "max_rss_kb": 56076,
  "mean_latency":   0.295871,
  "stddev_latency": 0.289569,
  "min_latency":    0.0,
  "max_latency":    1.793023,
  "distr_latency": {
    "25.0000": 0.06, "50.0000": 0.33, "75.0000": 0.39,
    "90.0000": 0.53, "95.0000": 0.69, "99.0000": 1.50,
    "99.9000": 1.79
  },
  "allocations": {
    "total_heap": 30175419,
    "minor_heap": 29735370,
    "major_heap": 4506106,
    "promoted_words": 4066057,
    "promoted_pct": 13.67
  },
  "collections": {
    "minor": 120,
    "major": 10,
    "forced_major": 0,
    "compactions": 0
  }
}
```

Extra fields (`domain_stats`, `domain_alloc_stats`) are preserved in
the raw record but not currently surfaced by the loader.

### 5.4 Perf sidecar schema

NDJSON. Each line is a list of counter records:

```json
[
  {"counter-value": "540932127.000000",
   "event": "cycles",
   "metric-value": "3.299467",
   "metric-unit":  "GHz"},
  {"counter-value": "954564407.000000",
   "event": "instructions",
   "metric-value": "1.764666",
   "metric-unit":  "insn per cycle"}
]
```

The loader flattens each entry into two DataFrame columns:
`perf_<event>` (the counter value) and `perf_<event>_<unit>` (the
derived metric, unit-normalised in the column name). Events absent
from the current `perf_grp` produce `NaN` columns.

### 5.5 Derived columns

Beyond the direct sidecar fields, the loader computes:

| Column | Definition |
|---|---|
| `variant` | `f"{version}/{flags}"` for grouping/legending |
| `max_rss_mb` | `max_rss_kb / 1024` |
| `olly_p50_latency_ms`, `olly_p95_latency_ms`, `olly_p99_latency_ms`, `olly_p999_latency_ms` | Pulled out of `distr_latency` |
| `major_per_minor` | `major_collections / minor_collections` |

### 5.6 `comparisons:` block in `runbms.yml`

running-ng materialises the resolved YAML config (post-`includes:` /
post-`overrides:`) into `<logs_dir>/runbms.yml` at the start of a run.
The notebooks read this file to learn which runtime pairs the
visualisation should render.

#### Schema

A top-level `comparisons:` key, holding a list of blocks:

```yaml
comparisons:
  - a:     <runtime>  |  [<runtime>, ...]
    b:     <runtime>  |  [<runtime>, ...]
    mode:  pairwise  |  cartesian      # optional; default pairwise
    label: "free-text label"           # optional; auto-generated if absent
```

`<runtime>` values are keys from the `runtimes:` block (e.g.
`ocaml-5.4.1-fp-flambda`). The notebook converts each runtime name to
its `variant` column value (`5.4.1/fp-flambda` in this example) by
stripping the `ocaml-` prefix and applying the same flag-suffix split
as the filename parser.

#### Modes

- **`pairwise`** *(default)* — zip `a` and `b` side-by-side. A scalar
  on either side is broadcast to match the opposite side's length
  (numpy-style). Lengths must match after broadcasting; otherwise an
  error is raised.
- **`cartesian`** — every `(x in a) × (y in b)` cross.

#### Examples

```yaml
comparisons:
  # 1:N broadcast — one runtime against many. Implicit pairwise.
  - label: "5.4.1 flag effects"
    a: ocaml-5.4.1
    b: [ocaml-5.4.1-fp, ocaml-5.4.1-flambda, ocaml-5.4.1-fp-flambda]

  # N:N pairwise — two equal-length lists, zipped.
  - label: "version effect (by flag combo)"
    a: [ocaml-5.4.1,    ocaml-5.4.1-fp,    ocaml-5.4.1-flambda,    ocaml-5.4.1-fp-flambda]
    b: [ocaml-d8bb46c,  ocaml-d8bb46c-fp,  ocaml-d8bb46c-flambda,  ocaml-d8bb46c-fp-flambda]

  # N×M cartesian — every cross. Explicit mode required.
  - label: "every cross"
    a: [ocaml-5.4.1, ocaml-5.4.1-fp]
    b: [ocaml-d8bb46c, ocaml-d8bb46c-fp, ocaml-d8bb46c-flambda]
    mode: cartesian
```

#### Default when absent

When the YAML omits a `comparisons:` block (or it's empty), the loader
returns one synthetic block: the notebook's `BASELINE` variable vs
every other variant present in the dataset. If `BASELINE` itself is
not in the dataset, the loader warns and falls back to the
alphabetically-first variant. This keeps simple PR-vs-baseline use
cases (proposal use case 2) working without any YAML editing — write
a `comparisons:` block when you have a multi-axis matrix where the
default would conflate effects.

#### Pairs that don't match the dataset

If a runtime name in a pair resolves to a variant that's not present
in the loaded DataFrame (e.g. the YAML was edited after the run, or a
benchmark only completed for some variants), the loader warns and
drops that pair. A block whose pairs are *all* dropped is omitted
entirely; if every block ends up empty, the loader warns and falls
back to the default.

## 6. Notebook A — Regression dashboard

**Answers:** did we regress? which benchmarks? by how much?

**Per-comparison structure.** Every detail section under §4
corresponds to one comparison block declared in `runbms.yml` (or
supplied via `COMPARISONS_OVERRIDE`). Each block is a self-contained
story: instruction-count deltas, wall-time / max-RSS / latency tornado
plots per pair, a tradeoff scatter restricted to the block's variants,
and ranked top-N regressions/improvements within the block. When the
YAML omits `comparisons:`, the loader falls back to a single default
block (`BASELINE` vs every other variant) — the rendered output is then
equivalent to a traditional single-baseline view.

**Configuration knobs.** Top of notebook:

```python
LOGS_DIR             = ...                 # path or BENCH_LOGS_DIR env var
BASELINE             = {"version": "5.4.1", "flags": "baseline"}
COMPARISONS_OVERRIDE = None   # or a list-of-dicts to bypass runbms.yml
TOP_N                = 10
WARN_PCT, REGRESS_PCT = 1.0, 3.0           # instruction-count thresholds
```

`COMPARISONS_OVERRIDE`: when not `None`, the notebook ignores the YAML
and uses this list instead — useful for ad-hoc exploration without
editing YAML or re-running benchmarks. Same shape as the YAML schema
(see §5.6).

**Runtime-agnostic.** Nothing hardcodes a specific number of compilers,
flag combinations, or benchmarks. Whether the dataset contains 2
runtimes (trunk vs. PR) or 8 (two versions × four flag combos), the
same cells render faceted views sized to fit.

**Sections:**

1. **Load.** Read or build the parquet cache. Print shape and the
   list of variants and benchmarks discovered.
2. **Sanity & schema.** Three checks before any plot:
   - completeness heatmap (benchmark × variant);
   - NaN audit;
   - schema-coverage warnings — runtimes declared in `runbms.yml` but
     no data in the dataset, and variants in the dataset but not
     covered by any comparison block (with a hint about
     `COMPARISONS_OVERRIDE`).
3. **Comparisons overview.** A single summary table with one row per
   declared block: pair count, datapoints, regression count, worst
   and best Δ%. The skim view that decides which §4 block to read
   first.
4. **Per-comparison detail.** One subsection per block, rendered by a
   loop. Each subsection contains, in order:
   - **Instruction-count Δ%** — deterministic signal; verdicts
     (`improvement` / `neutral` / `warn` / `regression`) using
     `WARN_PCT`/`REGRESS_PCT`.
   - **Wall-time Δ% tornado** — per pair, horizontal bars over
     benchmarks.
   - **Max RSS Δ% tornado** — same shape.
   - **p95 / p99 latency Δ% tornado** — gated on data presence.
   - **Time × memory tradeoff scatter** — restricted to this block's
     variants. The four-quadrant view (faster/lighter,
     slower/heavier, etc.) without the noise of variants from other
     blocks.
   - **Ranked tables (within block)** — top-N regressions and
     improvements for wall time, max RSS, GC overhead.
5. **CSV export.** Long-form: one row per (comparison, pair,
   benchmark) with all median Δ% columns. Writes to
   `cache/regression_report.csv` for sharing with reviewers who
   don't want to open Jupyter.

**Aggregation.** All "central value" calculations default to **median**
(see §9 for why).

**Styling.** matplotlib only, cells heavily commented because the
intended reader may be new to pandas.

## 7. Notebook B — Runtime behaviour explorer

**Answers:** what is the runtime actually doing? where is the time
going? is the distribution shape reasonable?

**Per-comparison structure.** B mirrors A's Option C layout: a small
all-variants diagnostic overview (§3) followed by per-comparison
detail (§4) where each block's plots are restricted to that block's
variants. Reading 4 colours on a plot instead of 8 is the difference
between "I can read the bars" and "I can't tell".

The diagnostic overview at the top exists for *pathology detection* —
spotting a variant whose distribution is dramatically off, or whose
IPC is suspiciously low. Without it, partitioning by comparison block
could hide a problem that lives in a variant the user is not focused
on.

**Configuration knobs.** Same as A — `LOGS_DIR`, `BASELINE`,
`COMPARISONS_OVERRIDE`. B reads the same parquet cache that A
populates.

**Sections:**

1. **Load.** Read or build the parquet cache. Print variants,
   benchmarks, invocation count, perf groups.
2. **Sanity & comparisons resolution.** Variant coverage check (same
   as A §2) plus declared/uncovered warnings; resolve the comparison
   blocks that drive §4.
3. **Diagnostic overview (all variants, once).** A compact set:
   - per-variant summary table with median wall time, GC overhead,
     promoted %, max RSS, IPC — scan for outliers;
   - automated pathology hints (e.g., "median IPC < 0.5 for variant
     X — possible memory pathology");
   - all-variants wall-time violin (one panel per variant) for
     spotting dramatic distribution shifts;
   - **per-benchmark operating envelope** — for each benchmark,
     aggregates wall time / GC overhead / collection counts /
     relative IQR across all variants × invocations and flags rows
     against the `ENVELOPE` thresholds set at the top of the
     notebook. Flags include `TOO_SHORT`, `TOO_LONG`,
     `NO_GC_PRESSURE`, `GC_PATHOLOGICAL`,
     `FEW_MAJOR_COLLECTIONS`, `HIGH_VARIANCE`. Tells you which
     benchmarks need calibration before drawing strong conclusions
     from the rest of the notebook.
4. **Per-comparison detail (loop).** One subsection per comparison
   block. Each subsection is filtered to that block's variants
   (the union of every variant appearing as `a` or `b` in any pair)
   and renders, in order:
   - **Wall time (raw)** — absolute seconds, bar = median, whiskers = IQR.
   - **Mutator vs GC time** — stacked bars per variant, per benchmark.
     Reveals when a small wall-time ratio hides a GC explosion.
   - **GC overhead %** — bars per variant per benchmark.
   - **Latency ECDF** — empirical CDF per variant, gated on
     `distr_latency` columns being populated.
   - **Wall-time violins** — distribution per (benchmark, variant)
     across invocations. Bimodal shapes signal measurement
     contamination. Skipped when invocations per cell ≤ 1.
   - **Promoted %** — fraction of minor-heap words that survived
     promotion to the major heap.
   - **Hardware counters (absolute)** — IPC and page-fault rate when
     the perf group provides them; otherwise skipped with a note.
5. **ministat export.** Pick a benchmark and two variants; the
   loader writes two newline-separated files of raw measurements
   and prints the `ministat` command to run.

**Styling.** seaborn allowed (violin / ECDF look noticeably cleaner).
Researcher audience.

## 8. How to run

### 8.1 Environment

From the repository root:

```bash
python3 -m venv .venv-notebooks           # or reuse running-env
source .venv-notebooks/bin/activate
pip install -e .[notebook]
```

This pulls in `jupyterlab`, `pandas`, `numpy`, `matplotlib`, `seaborn`,
and `pyarrow`. The base `running-ng` install stays lightweight — the
notebook extras are opt-in.

### 8.2 Launch and order

```bash
cd notebooks/
jupyter lab
```

Open `A_regression_dashboard.ipynb` first. Its first real cell builds
(or refreshes) `cache/macrobench.parquet`. Then open
`B_runtime_behaviour.ipynb`, which reads the cache.

### 8.3 Pointing at a log directory

Both notebooks resolve the log directory from the environment variable
`BENCH_LOGS_DIR`, falling back to an in-notebook default if the
variable is unset:

```python
LOGS_DIR = os.environ.get("BENCH_LOGS_DIR") or "<path edited at the top of the notebook>"
```

For a one-off view, edit the fallback path in the top cell. For
scripted / CI use, export `BENCH_LOGS_DIR` before launching Jupyter:

```bash
BENCH_LOGS_DIR=/path/to/your-run-logs jupyter lab
```

The loader does not care what the directory is called or where it
lives — anything following the filename scheme in §5.2 will load.

### 8.4 Cache invalidation

The parquet cache is a pure function of the log directory. Re-running
A over the same log dir re-builds the cache; deleting
`cache/macrobench.parquet` forces a rebuild. The cache is in
`.gitignore`.

## 9. Methodology notes

These notes capture the reasoning behind a few non-obvious choices.
They come from running-ng's own usage, internal feedback from the
benchmarking team, and references in the benchmarking proposal
(Chen et al. 2012, Le Boudec 2010).

### Median rather than mean

When the number of invocations per cell is small — and "small" here
means fewer than roughly 100 — the central limit theorem does not
apply. The sample mean can be far from the population mean, and the
sample standard deviation can produce confidence intervals that
contain negative times. The median is robust to skew and to the
outliers that inevitably appear when a benchmark machine has a bad
minute. `baseline_normalize` and `aggregate_invocations` in the
loader both default to median; mean is available as an option.

### Raw measurement export

Benchmarks should report the full raw data they captured, not just
average and standard deviation. This lets downstream tools
(`ministat`, bespoke statistical notebooks, workload-diversity PCA)
work without requiring a re-run. Notebook B exposes a one-click
ministat export: given a benchmark and two variants, it writes
plain-text files of one measurement per line.

### Violin plots for distribution shape

A mean or median summarises a distribution; a violin plot *shows* it.
Multi-modal distributions — two bumps where there should be one — are
the visual signature of measurement contamination: CPU frequency
drift, a background process, filesystem cache state, or (famously) a
negotiated NFS version changing between runs. A violin plot exposes
those failure modes at a glance. The notebook gates this view on
`n > 1` because a violin of one point is just a dot.

### Instruction counts as a deterministic signal

Wall-clock time is noisy; it needs tens of samples to make a
significant-change claim. Instruction counts, collected via
`perf stat -e instructions` or Cachegrind, are **deterministic** for
a given program and input. A 0.1% change is detectable in 3–5 runs.
Notebook A surfaces instruction-count deltas as a headline table
because that is the cleanest regression signal available today.
The wider benchmarking plan makes instruction counts the primary
signal for PR-level regression detection, with wall time reported
alongside as the "impact" signal.

## 10. Known limitations (as of 2026-04-23)

- **Small invocation count (N = 3 in the prototype dataset).** Enough
  to compute a median and an IQR, enough to draw a violin, enough to
  feed `ministat`. Not enough for a Wilcoxon + Cliff's Delta claim at
  95% confidence — the proposal's Phase 3 guidance is `N ≥ 30` for
  wall-time and `N ≥ 5` for instruction counts. Bump the `invocations`
  setting in the runbms YAML and re-run to unlock significance tests.
- **No confidence intervals or significance tests.** IQR is
  descriptive; the statistical layer (Wilcoxon / Cliff's Delta /
  Hierarchical Speedup) is future work.
- **No OS / BIOS / CPU-frequency metadata on plots.** Surfacing this
  needs running-ng (or the tool wrappers) to write a system-state
  sidecar. None exists today.
- **perf group is fixed per run.** Whichever `perf_grp` was configured
  determines which counters are available. The notebooks render
  whatever columns are present and skip the rest with a note — so
  cache/TLB/topdown views light up automatically when a run with the
  right group appears.

## 11. Planned work

- **Wilcoxon rank-sum + Cliff's Delta.** The principled replacement
  for the simple-ratio "top regressions" table. Wilcoxon is a
  non-parametric significance test; Cliff's Delta is the effect-size
  companion. Landing this needs `N ≥ 30` wall-time invocations.
- **Hierarchical Speedup at 95%.** The largest speedup that can be
  proven at the 95% confidence level. Reported alongside the simple
  ratio; a large gap between the two flags measurement-environment
  noise.
- **Workload-diversity PCA.** Principal components over per-benchmark
  metric vectors, to show which benchmarks exercise distinct runtime
  behaviour and which are redundant. Its own notebook once the data
  supports it.
- **System-state surfacing.** Render a per-run metadata card when
  running-ng starts writing uptime / CPU frequency / tuned status /
  NFS version / BIOS info into sidecars.
- **Notebook C — GC parameter sweep.** Landed. Heatmaps and Pareto
  scatters per (variant, sub-sweep) across whichever of
  `{s, o, M, m}` actually vary; "three best" config picks (best wall,
  best RSS, best Pareto) with worst-case per-benchmark regression
  surfaced; cross-runtime Δ% heatmaps driven by `runbms.yml`'s
  `comparisons:` block.

## 12. Out of scope

The following are covered elsewhere in the broader benchmarking
project and are explicitly **not** goals for these notebooks:

- CI integration and PR bot feedback loops.
- Result ingestion into a persistent SQLite or Postgres store.
- Compiler-throughput benchmarking.
- GC traces (full recording of GC roots).
- USDT probe integration beyond what already lands in the olly
  sidecar.
- The final web dashboard (Vega-Lite or FastAPI + JS). That is a
  later-phase, OCaml-implemented deliverable; these notebooks are
  the prototyping substrate that informs its design.
