# merlin

Merlin is the IDE engine for OCaml. `merlin_bench` exercises the experimental
`merlin-domains` branch, which moves the typer onto its own domain and hands partial
results back while typing continues in parallel — the suite's only 2-domain
steady-state workload (cross-domain GC marking + the pacer under two real domains,
effects for cancellation, atomics for the shared channel). It replays merlin's own
cram-bench queries (construct / complete-prefix / case-analysis) against a 51k-line
synthetic input, in a loop of `argv.(1)` iterations. When it ran: ~16s at arg=4, gc%
~24%, RSS ~1 GB.

**Disabled — no ladder.** It is not in the default run set (`benchmarks: []`).

## Disabled

An upstream race in `merlin-domains` (not this repo) crashes the run: at N≥2
iterations the typer trips `Types.rev_log -> Invalid -> assert false` (a domain walks a
type-environment trail a prior backtrack marked invalid). Non-deterministic; fires on
almost every 5.4.1 run and ~half of N=2 runs on 5.5-beta (d8bb46c) — so it is a
`merlin-domains` bug, not an ABI mismatch. Likely cause (per
[ocaml/merlin#1890](https://github.com/ocaml/merlin/pull/1890)): removing laziness for
concurrency left `Local_store` scope not isolated between the two domains. Full repro:
`benchmarks/merlin/UPSTREAM_BUG.md`. Re-enable by uncommenting `merlin_bench` in
macro_base.yml's `benchmarks:` once fixed.
