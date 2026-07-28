# frama-c

Frama-C is a static-analysis platform for C. This benchmark runs its EVA plugin (Evolved
Value Analysis, an abstract-interpretation / value analysis) over a C program. There are two
programs, differing only in which C source EVA is pointed at. Both run as a single
observable OCaml process.

## What it runs

| program | analysed source | size | EVA config |
| --- | --- | --- | --- |
| `frama_c_eva_t` | `t.c` (the zlib source) | ~17.5k lines | `-eva-slevel 100` (fixed; standalone, not a ladder rung) |
| `frama_c_eva_sqlite` | `sqlite3.c` (SQLite amalgamation) + `sqlite_driver.c` | ~258k lines | `-eva-precision 0` (legacy / tag anchor, == the `_small` rung) |
| `frama_c_eva_sqlite_small` | same | | `-eva-precision 0` |
| `frama_c_eva_sqlite_default` | same | | `-eva-precision 2` |
| `frama_c_eva_sqlite_large` | same | | `-eva-precision 3` |

`eva_t` analyses the zlib source directly. `eva_sqlite*` analyse the full SQLite
amalgamation, entered through a tiny driver (`sqlite_driver.c`) whose `main` opens an
in-memory database and runs a couple of statements, giving EVA a `main` to analyze against.

Both workloads run with `-eva -eva-no-results`. The wrapper selects a workload by its first
argument (`t` or `sqlite`); for `sqlite`, an optional **second argument is the EVA precision
level** (`-eva-precision 0..11`, default 0; also settable via `FRAMAC_EVA_PRECISION`). This
precision level is the **Knob-A axis** — see the ladder section below. (`eva_t` still reads
`FRAMAC_EVA_SLEVEL`, default 100, but that knob does nothing on t.c; the file is too small
to accumulate states.)
The sqlite run also downgrades the `assigns:missing` warning from error to feedback, because
the amalgamation calls spec-less libc/OS functions that would otherwise abort the analysis;
the goal is to keep it analysing, not to prove soundness.

The build is a bit unusual. Frama-C 32.1 is vendored as source (`scripts/vendor-frama-c.sh`
into `vendor/frama-c`), and only its kernel plus EVA are built. WP (and its `why3`
dependency, which would cap OCaml below 5.5) and the GUI/apron plugins are left out.
`benchmarks/frama-c/dune` links a standalone executable statically with `-linkall`, driven
by an empty `frama_c_eva.ml`: the behaviour comes entirely from link-time registration
side effects, mirroring Frama-C's own `frama-c` binary. The one ordering constraint is that
`frama-c-eva.core` must be linked before `frama-c.boot`, so EVA's `Plugin.Register` runs
before boot finalises the command-line option table (otherwise `-eva` is an unknown flag).

Because it is a static build, it runs with `-no-autoload-plugins` (there is no plugin site
to discover), and the wrapper sets `DUNE_DIR_LOCATIONS` to point Frama-C's otherwise-empty
`share`/`lib` sites at `vendor/frama-c`. The output `frama-c-<runtime>` is a wrapper script
that execs the real `.exe` inside the per-runtime build dir.

## What it stresses

This is the suite's largest weak / ephemeron hash-consing workload. Frama-C hash-conses its
entire CIL AST, and EVA hash-conses its abstract state, through
`State_builder.Hashconsing_tbl_weak`, which is OCaml's `Weak.Make` and so is
ephemeron-backed in the runtime. On the 258k-line SQLite input this is a genuinely large
weak-table workload. Alongside that:

- Recursive-variant allocation for the CIL AST.
- `Hashtbl` and minor-GC allocation in EVA's core abstract interpreter.

## Knob-A ladder (precision)

The Knob-A axis is **EVA precision** (`-eva-precision N`), passed as the `sqlite` wrapper's
second argument. Measured on OCaml 5.5.0, Ryzen 9 9950X (`fingerprint.sh`, `v=0x400`):

| rung | prec | wall | RSS | minor GC | allocated | live heap (top_heap_words) |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 0 | 7.3s | 457 MB | 11k | 3.0 G | 53.6 M |
| `_default` | 2 | 17.8s | 641 MB | 31k | 8.2 G | 77.0 M |
| `_large` | 3 | 124s | 695 MB | 182k | 47.9 G | 84.1 M |

small→default→large passes the acceptance test: RSS, live heap, and minor-GC / allocation
churn all grow, so each rung reaches a GC regime the one below did not. The regime that
grows is exactly the ocaml#11733 one — weak/ephemeron hash-consing of the CIL AST + EVA
state — with `_large` maximally exercising the ephemeron-cleaning path (182k minor
collections, each triggering a weak-table key scan).

olly gc-profile (running-ng `perf_grp1|re-25|md-2`, 5.5.0, one invocation; harness clean —
no lost/corrupt events):

| rung | wall | gc% | gc_time | max_rss_kb_excl_ring | max pause | p99.9 pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 6.5s | 12.9% | 0.85s | 503 MB | 3.1 ms | 1.44 ms |
| `_default` | 16.0s | 10.9% | 1.74s | 704 MB | 8.9 ms | 1.45 ms |
| `_large` | 113s | 2.9% | 3.27s | 768 MB | 11.5 ms | 0.45 ms |

Complementary coverage (same shape as zarith): **gc% falls with size** — small/default are
GC-throughput-sensitive, while at `_large` the widening-thrash mutator dominates so GC is a
smaller fraction even as absolute `gc_time` grows — and **tail pauses grow** (3→11.5 ms), so
`_large` is GC-latency-sensitive (ocaml#14796 territory). The ladder is not redundant.
(`max_rss_kb_excl_ring` runs ~40-70 MB above the ring-free `/usr/bin/time` RSS because it
strips only the events ring, not olly's own tracing-domain overhead; for pure footprint
prefer the `/usr/bin/time` numbers above.)

CAVEAT (olly minor-allocation units bug, diagnosed 2026-07-27): at precision 0, olly's
`minor_heap` reads **exactly 8x** the runtime's `Gc.stat` `minor_words` (17.79 G vs 2.23 G;
ratio 7.97 = the machine word size), i.e. it is carrying **bytes, not words**. Everything
else agrees to <1%: `promoted_words`, `major_words`, and both minor/major collection counts.
This is a confirmed **OCaml 5.5.0 runtime bug** (verified by a self-monitoring `Runtime_events`
repro): `EV_C_MINOR_ALLOCATED_WORDS` emits *bytes* — the same value as `EV_C_MINOR_ALLOCATED`,
~8× `Gc.minor_words` — despite being documented as words. Its siblings `EV_C_MINOR_PROMOTED_WORDS`
and `EV_C_MAJOR_ALLOCATED_WORDS` are correct (words), which is why only the minor figure is off.
olly's 5.5 shim reads `_WORDS` trusting the docs and just receives bytes (olly is not at fault;
not ring loss, not an enum skew — olly and the runtime are both release 5.5.0). It does **not**
affect any number in this doc — gc%/pauses/RSS/collection counts come
from correct sources, and the ladder's allocation figures are `Gc.stat` (`v=0x400`), not olly.
(An earlier note here claimed "~6-7x, fewer collections"; that was an artifact of comparing a
precision-0 olly run against a slevel-0 fingerprint — different EVA configs. Same-config it is
a clean 8x on minor allocation only.)

Two findings shaped this ladder, both contradicting the earlier `-eva-slevel` hypothesis:

- **`-eva-slevel` is a dead knob here.** Sweeping it 0→2000 leaves the fingerprint flat on
  both t.c (0.39s every time) and sqlite (~7s, RSS ±3%). Without loop unrolling EVA merges
  abstract states immediately, so raising the per-path state cap changes nothing.
  `-eva-precision` is what moves the analysis, because it also turns on loop unrolling,
  richer domains (equality, symbolic-locations, gauges, octagon), and higher plevel/ilevel.
- **Precision is non-monotone in wall time and saturates in RSS (~730 MB).** `_large`
  (precision 3) is a deliberate outlier: its `-eva-auto-loop-unroll 64` lands just below a
  sqlite loop bound, so EVA fails to unroll it and thrashes through widening — 124s and 48 G
  allocated. Precision 4-9 collapse back to ~8s (the loop unrolls cleanly at limit 96+), and
  even precision 11 (biggest live heap, 88.9 M words / 732 MB) runs in only 13s. The cliff is
  a deterministic property of `Frama-C 32.1 + sqlite3.c + precision 3`, all fixed across the
  OCaml runtimes we compare, so it is stable *as a benchmark* even though it is a "bad" EVA
  config for verification. It is the config that stresses the runtime path we care about
  hardest, which is what a GC benchmark wants.

**No `huge` (>5 min) rung** is reachable via any EVA knob — precision saturates and slevel is
inert. A true huge rung would need a genuinely bigger C amalgamation (bigger CIL AST = more
hash-consing), which is a corpus-sourcing task; it is deferred honestly rather than faked
with repetition.

## Reading the results

Rough baseline numbers:

- `eva_sqlite` / `_small` (precision 0): wall ~7s, RSS ~460 MB (100 of 2529 functions, 1846
  statements analysed). Building and running was verified to give identical analysis output
  on 5.4.1, d8bb46c (a 5.5 beta) and trunk.
- `eva_t` is small and fast (~0.4s on 5.5.0); it is a fixed standalone, not a ladder rung —
  neither slevel nor precision scales it (the file is too small for EVA to accumulate state).

The headline signals are `max_rss_kb` and `wall_time`, ideally across the precision ladder
(`_small`/`_default`/`_large`). `eva_sqlite` is the reproducer for ocaml#11733, Frama-C's 3-5x RSS / startup
regression on OCaml 5, which is rooted in the ephemeron-cleaning path. If `eva_sqlite`
(huge AST) moves but `eva_t` (small) does not, suspect weak-table / ephemeron-clean scaling.
If both move, look at EVA's core abstract interpreter or minor-GC allocation. If Frama-C and
alt-ergo (the other `Weak.Make` workload) move together but nothing else does, that strongly
points at weak / ephemeron-pointer cleaning.

## Notes

Frama-C is pinned at 32.1 and vendored by hand; the vendor script also fills in the
`share`/`lib` resource trees the analysis needs (machine descriptions, the libc model that
preprocesses the analysed C source).
