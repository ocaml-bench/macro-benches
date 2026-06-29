# MMTk macro panel — `ocaml-mmtk@e52418f`, GC-thread sweep (default vs `MMTK_THREADS=1`)

**Setup.** `ocaml-mmtk` = [fplaunchpad/ocaml-mmtk](https://github.com/fplaunchpad/ocaml-mmtk) `5.5+mmtk` @ `e52418f` (`ocaml-variants.5.5.0`); stock = OCaml `5.5.0-rc1` (`4090d6db`, the fork point). Native, **dynamic heap** (MemBalancer; `MMTK_HEAP_SIZE_MB` unset), **best-of-3** wall time (min), `/usr/bin/time`. Driven by running-ng (`experiments/mmtk_thread_compare.yml`), ASLR off (`setarch -R`). Host: 32-core Linux x86-64. Raw logs: `logs/raw_logs.tar.gz`.

GenImmix (default plan) and Immix, each under **two GC-thread settings**: the default worker count (parallel STW GC, ≈ ncores) and **`MMTK_THREADS=1`** (single GC worker — the fair, sequential-GC comparison for these single-domain programs).

## Wall-time ratio (mmtk / stock; lower = better)

| benchmark | stock (s) | GenImmix def | GenImmix T1 | Immix def | Immix T1 |
|---|--:|--:|--:|--:|--:|
| alt_ergo_fill | 5.17 | 7.27 ⚠️ | 8.17 | 1.28 | 1.93 |
| alt_ergo_yyll | 6.78 | 2.37 | 2.49 | 1.30 | 1.59 |
| coqc_corelib_stress | 3.52 | 1.00 | 0.99 | 1.00 | 1.00 |
| cpdf_blacktext | 2.51 | 1.32 | 1.73 | 1.12 | 1.49 |
| cpdf_merge | 2.18 | 1.60 | 2.30 | 0.95 | 1.37 |
| cpdf_scale | 12.91 | 1.07 | 1.40 | 0.95 | 1.21 |
| cpdf_squeeze | 3.49 | 1.48 | 1.83 | 1.04 | 1.29 |
| devkit_gzip | 2.52 | 1.02 | 0.95 | 1.03 | 1.04 |
| devkit_network | 4.98 | 1.40 | 1.28 | 1.28 | 1.39 |
| devkit_stre | 4.11 | 1.34 | 1.16 | 1.13 | 1.10 |
| eio_fiber_stream | 2.05 | 2.10 | 1.88 | 1.27 | 1.25 |
| frama_c_eva_sqlite | 7.08 | 0.97 | 1.10 | 1.58 | 1.90 |
| frama_c_eva_t | 0.39 | 1.51 | 1.54 | 2.28 | 3.03 |
| goblint | 0.21 | 1.81 | 1.62 | 1.71 | 2.14 |
| irmin_mem_rw | 4.02 | 1.10 | 1.07 | 1.22 | 1.31 |
| jsoo | 3.74 | 1.44 | 2.01 | 1.04 | 1.32 |
| liq_parse_typecheck | 9.64 | 1.82 | 1.47 | 1.16 | 1.15 |
| menhir_ocamly | 12.73 | 1.26 | 2.00 | 1.41 | 2.17 |
| menhir_sql_parser | 1.23 | 1.60 | 2.01 | 1.39 | 2.50 |
| menhir_sysver | 7.80 | 1.44 | 2.10 | 1.04 | 1.79 |
| ocamlc_self_compile | 3.36 | 1.85 | 2.60 | 1.60 | 2.26 |
| ocamlformat_rocq | 1.86 | 1.72 | 1.88 | 1.47 | 1.94 |
| owl_gc | 3.04 | 0.77 | 0.74 | 1.05 | 1.04 |
| test_decompress | 1.70 | 1.64 | 1.46 | 1.23 | 1.17 |
| ydump_repeat | 2.53 | 1.02 | 1.00 | 0.98 | 0.96 |
| zarith_pi | 2.35 | 1.12 | 0.75 | 0.97 | 0.74 |

### Geomean (×stock, n=26, excl. timelimit-bound `alt_ergo_unsat_smt2`)

| plan | default GC threads | `MMTK_THREADS=1` |
|---|--:|--:|
| **GenImmix** | **1.47×** | **1.59×** |
| **Immix** | **1.22×** | **1.46×** |

## Takeaways

- **`MMTK_THREADS=1` is slower on average** — with the default thread count, parallel STW GC uses the idle cores to finish collections faster. The THREADS=1 numbers are the honest single-threaded-GC overhead (fair for single-domain programs); the default-thread numbers are MMTk-favorable. The gap is largest on GC-heavy compile benches (menhir, cpdf, jsoo, ocamlc), which parallelize collection well.
- **A few flip to *faster* under `MMTK_THREADS=1`** — `zarith_pi` (1.12→**0.75**; Immix 0.97→**0.74**), `owl_gc` (0.77→0.74), `liq_parse_typecheck`, `devkit_stre`/`network`, `test_decompress` — i.e. parallel GC threads were net *overhead* there (notably the GMP/Bigarray custom-block benches).
- `alt_ergo_fill` GenImmix **7.3×** ⚠️ remains a real outlier (GMP custom blocks vs the copy-nursery).

## Crash / hang status on `e52418f`

- ✅ **alt-ergo moving-GC SIGSEGVs are fixed** (all 3 run under the moving GenImmix/Immix plans).
- ❌ **Excluded — hang** (intermittently, under *both* the default thread count *and* `MMTK_THREADS=1`): `sedlex_tokenize`, `devkit_htmlstream`, `liq_video_frames_pool`. These are single-domain programs, so the hang is in MMTk's GC machinery, not mutator parallelism.
- ❌ **Excluded — SIGABRT** `try_lock`: `pplacer_testsuite` — the cross-domain channel-finaliser residual of [issue #11](https://github.com/fplaunchpad/ocaml-mmtk/issues/11) (the single-domain case is fixed; the cross-domain registration is not yet deferred).
