# frama-c

Frama-C is a static-analysis platform for C. This benchmark runs its EVA plugin (Evolved
Value Analysis, an abstract-interpretation / value analysis) over a C program. There are two
programs, differing only in which C source EVA is pointed at. Both run as a single
observable OCaml process.

## What it runs

| program | analysed source | size | default slevel |
| --- | --- | --- | --- |
| `frama_c_eva_t` | `t.c` (the zlib source) | ~17.5k lines | `-eva-slevel 100` |
| `frama_c_eva_sqlite` | `sqlite3.c` (SQLite amalgamation) + `sqlite_driver.c` | ~258k lines | `-eva-slevel 0` |

`eva_t` analyses the zlib source directly. `eva_sqlite` analyses the full SQLite
amalgamation, entered through a tiny driver (`sqlite_driver.c`) whose `main` opens an
in-memory database and runs a couple of statements, giving EVA a `main` to analyze against.

Both workloads run with `-eva -eva-no-results`. The slevel (how aggressively EVA keeps
separate abstract states per path) is set from the `FRAMAC_EVA_SLEVEL` environment variable.
Note the defaults differ: `eva_t` defaults to slevel 100, `eva_sqlite` to slevel 0. Raising
`FRAMAC_EVA_SLEVEL` pushes both wall time and RSS up, so it is the main knob for a sweep.
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

## Reading the results

Rough baseline numbers:

- `eva_sqlite`: wall around 7-8s and RSS around 460 MB at slevel 0 on trunk (100 of 2529
  functions, 1846 statements analysed). Building and running was verified to give identical
  analysis output on 5.4.1, d8bb46c (a 5.5 beta) and trunk.
- `eva_t` is the smaller of the two.

The headline signals are `max_rss_kb` and `wall_time`, ideally under a `FRAMAC_EVA_SLEVEL`
sweep. `eva_sqlite` is the reproducer for ocaml#11733, Frama-C's 3-5x RSS / startup
regression on OCaml 5, which is rooted in the ephemeron-cleaning path. If `eva_sqlite`
(huge AST) moves but `eva_t` (small) does not, suspect weak-table / ephemeron-clean scaling.
If both move, look at EVA's core abstract interpreter or minor-GC allocation. If Frama-C and
alt-ergo (the other `Weak.Make` workload) move together but nothing else does, that strongly
points at weak / ephemeron-pointer cleaning.

## Notes

Frama-C is pinned at 32.1 and vendored by hand; the vendor script also fills in the
`share`/`lib` resource trees the analysis needs (machine descriptions, the libc model that
preprocesses the analysed C source).

### Why the wrapper pins two preprocessor macros

`sqlite3.c` is preprocessed with the host's C preprocessor and branches on compiler
feature macros, so without care **different machines analyse different programs**. Two
such branches mattered enough to pin, and the wrapper passes
`-cpp-extra-args="-DLONGDOUBLE_TYPE=double -D'__has_extension(x)=1'"` to fix both. (The
inner quotes are needed because Frama-C runs the preprocessor through a shell, which
would otherwise choke on the `(`.)

**`__has_extension` — a 25x performance cliff.** Frama-C preprocesses with
`gcc -E -undef -imacros __fc_builtin_macros.h`, so `__GNUC__` is stripped and sqlite3.c's
`GCC_VERSION` is 0 on *every* host. Its atomics gate is therefore decided entirely by the
second half of

```c
#if GCC_VERSION>=4007000 || __has_extension(c_atomic)
```

and sqlite3.c self-guards `#ifndef __has_extension` → `#define __has_extension(x) 0`. So
the branch hinges purely on whether the host gcc predefines `__has_extension`, which is a
**gcc ≥ 14** feature:

| host gcc | `AtomicLoad` becomes | EVA sees | wall |
|---|---|---|---|
| ≥ 14 | `__atomic_load_n(...)` | an undeclared function — cheap and imprecise | 7s |
| ≤ 13 | the real `volatile`/mutex code | a far larger state space | >180s, no convergence |

Measured on one machine by flipping only that macro: 7s versus still running at a 180s
cap. Forcing it to 1 makes every host take the intrinsics path the benchmark was
characterised on.

**`LONGDOUBLE_TYPE` — an outright abort.** sqlite3.c decides at runtime whether to use
long doubles via `sqlite3Config.bUseLongDouble = sizeof(LONGDOUBLE_TYPE)>8`. Where that
gate is true, EVA enters the branch and Frama-C 32.1 aborts with
`unimplemented feature ... Builtins for long double type` (exit 3). Setting the type to
`double` — SQLite's documented override — makes the gate false everywhere. Measured cost:
`bUseLongDouble` becomes 0 and one alarm of 87 disappears (a signed-overflow alarm inside
the long-double detection code itself); the other ~12k log lines are identical and wall
time is unchanged.

With both pinned, the analysed program no longer depends on the host compiler, so results
are comparable across machines. If you ever change these flags, expect the alarm count
and the wall time to move.
