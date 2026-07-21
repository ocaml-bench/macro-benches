# merlin

Merlin is the IDE engine for OCaml (completion, type-at-point, case analysis,
and so on). This benchmark (`merlin_bench`) exercises the experimental
`merlin-domains` branch, which moves the typer onto its own domain and hands
partial results back to the main domain while typing continues in parallel.

**This benchmark is currently disabled.** The `merlin-domains` branch has a
non-deterministic race that crashes the run. Details below.

## What it runs

One program, `merlin_bench` (built from `merlin_bench.ml`). It replays the 7
queries from merlin's own cram bench
(`tests/test-dirs/server-tests/bench.t/run.t`) against a large synthetic input
file, `ctxt.ml` (51,319 lines), in a loop of N iterations. The queries are:

- one `construct`
- three `complete-prefix` (at lines 109, 51152, 51319)
- three `case-analysis` (two at line 50796, one at 51318)

The two consecutive case-analyses at the same position are deliberate: they
test the typer cache and the partial-typing handoff.

The driver runs in-process and does the same `Domain.spawn @@
Mpipeline.domain_typer` dance that `ocamlmerlin_server` does in `single` mode,
so it exercises the real production code path inside one observable process
(two domains exactly: main plus the typer worker). The build produces a small
wrapper script that sets `MERLIN_BENCH_CTXT` to the absolute path of `ctxt.ml`
and execs the binary; the binary reads the iteration count from `argv.(1)`
(default 1). The measured profile below is at arg=4.

## What it stresses

- `Domain.spawn` / `Domain.join` and cross-domain communication. This is the
  only 2-domain steady-state workload in the suite. Pipeline results computed
  on the typer domain end up reachable from main, so it exercises cross-domain
  GC marking and the major-heap pacer under two real domains.
- Effects, for the partial-typing and cancellation control flow (a query can be
  aborted mid-run when a new one arrives).
- Atomics, for the cancellation flag and the shared message channel
  (`Domain_msg.t`).
- A realistic OCaml typer workload: `Env`, `Typecore`, `Typeclass`, and the
  typer's caching layer.

## Reading the results

When it was running, expect a wall time of around 16s at arg=4, GC overhead
near 24%, and RSS around 1 GB. The interesting signal is cross-domain: movement
here without movement on the single-domain benchmarks points at `Domain.spawn`
cost, cross-domain marking, or the pacer's behaviour with two producers.

## Notes

Disabled because of an upstream race in `merlin-domains`, not because of
anything in this repo. On workloads of N >= 2 iterations the typer trips
`Types.rev_log -> Invalid -> assert false`: the typer is asked to walk a piece
of the type-environment trail that a prior backtrack already marked invalid,
which should never happen single-threaded. The crash is non-deterministic. It
fires on almost every run against 5.4.1 and on roughly half of N=2 runs against
5.5-beta (d8bb46c). Because it fires on 5.5-beta too, it is a `merlin-domains`
bug and not an OCaml ABI mismatch, even though the branch's vendored typer is
synced from an older OCaml 5.3 snapshot. The branch's own PR
([ocaml/merlin#1890](https://github.com/ocaml/merlin/pull/1890)) flags the
likely cause: removing laziness for concurrency left the `Local_store` scope
not fully isolated between the two domains. Full repro and analysis live in
`benchmarks/merlin/UPSTREAM_BUG.md`.

The source is kept in the tree; the benchmark is disabled by emptying its
programs list in the orchestrator config. Re-enable it once upstream fixes the
race.

Build quirks worth knowing if you try to build it by hand:

- It builds **without** `--profile release`. Under release, dune uses the
  branch's checked-in `parser_raw.ml`, which references a MenhirLib static
  version that does not match the bundled `menhirLib.ml`. The dev profile lets
  menhir regenerate `parser_raw.ml` so the versions line up.
- The branch's `gen_config.ml` only enumerated OCaml versions up to 5.3, so
  5.4.1 / 5.5 / trunk fail to compile until patched. `scripts/setup-monorepo.sh`
  applies that patch.

Requires OCaml 5.5+ to actually run correctly (the vendored typer targets the
5.5 ABI); older compilers trip an unrelated assertion inside the typer.
