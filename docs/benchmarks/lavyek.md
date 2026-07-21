# lavyek

Lavyek is a from-scratch multicore key-value store for OCaml: Eio for fiber
scheduling, io_uring for its write-ahead log, and hand-rolled atomic structures
for the in-memory index. This benchmark (`lavyek_bench`) runs a fixed-work
write-then-read load across a configurable number of domains, so the interesting
output is how wall time scales as you add domains.

**This benchmark is currently disabled.** Lavyek lives in a private repository,
so it is not cloned or built by default. The benchmark definition stays in the
tree (its `duniverse/lavyek/` source is simply absent), and
`setup-monorepo.sh` skips the clone. Re-enable it once you have access to the
repo.

## What it runs

Four cells, all from the same `lavyek_bench.ml` driver, differing only in the
number of domains:

| Cell           | Domains |
| -------------- | ------- |
| `lavyek_kv_1d` | 1       |
| `lavyek_kv_2d` | 2       |
| `lavyek_kv_4d` | 4       |
| `lavyek_kv_8d` | 8       |

Each run does a WRITE phase (put `nb` key-value pairs) then a READ phase (look
them all back up and check the values match). Keys are 24 bytes, values 100
bytes. Work is handed out by a shared `Atomic.fetch_and_add` chunk counter, and
each domain runs 100 fibers concurrently against that counter. The default
`nb` is 10,000,000 pairs, so every cell does the same 10M-op budget and the
walls reflect parallel scaling rather than different amounts of work.

The driver takes positional args: `nb_domains` (default 4), `max_fibers`
(default 100), `nb` (default 10,000,000), and `dbpath` for the WAL. Each worker
domain pins itself to a physical core (the `smt=0` sibling) via
`ocaml-processor` as its first action, so domain i lands on the same core every
run. Without that pinning, the kernel migrates domains around and multi-domain
walls stop being reproducible.

## What it stresses

- Multi-domain parallelism via Eio's `Domain_manager.run` (real OS threads).
  The 1d-to-8d curve is the whole point.
- Effects, and a lot of them: `Fiber.fork_promise`, `Fiber.all`, `Fiber.yield`
  all go through effect performs, spread across every domain. This is far more
  effect traffic than `eio_fiber_stream`.
- Hand-rolled `Atomic.*` structures for the in-memory index and the shared
  chunk dispatcher (`Atomic.compare_and_set` / `Atomic.fetch_and_add` loops).
  At 8 domains the contention on the dispatch counter is itself measurable.
- io_uring, via `eio_linux`, for the per-domain WAL writes. Each domain spins
  up its own `iou-wrk` kernel-side helper thread.
- Per-domain CPU affinity via `pthread_setaffinity_np` (through
  `ocaml-processor`). This is the only benchmark in the suite that touches it.

## Reading the results

When it was running (Ryzen 9 9950X, `re=22`, `md=8`), the walls were roughly:
1d around 25s, 2d around 14s, 4d around 8s, 8d around 6s. The 4-domain cell is
the calibrated target and 1d is the serial baseline. I/O matters: on a slow
disk the WAL writes flatten the curve, and on tmpfs you get near-ideal scaling
out to 4 domains with diminishing returns at 8d (GC pacer plus cross-domain
contention). What to look at is the *shape* of the 1d-to-8d curve, not any
single cell: a change in curve shape points at the major-heap pacer,
cross-domain marking, or stop-the-world cost, while a shift on 1d alone points
at the single-domain Eio / io_uring path.

## Notes

Requires OCaml 5.2+ (Eio 1.x). Needs `md=8` and a smaller per-domain
runtime-events ring (`re=22`) when re-enabled, wired via lavyek-only `re_par` /
`md_par` modifiers in the orchestrator config.

Two things in the driver do not match how the README describes lavyek, worth
knowing before you trust either:

- The driver's own header comment says kcas is used "under the hood." It is
  not. Lavyek's `dune-project` lists `kcas` and `kcas_data` as dependencies but
  the actual source never references them; the in-memory index is hand-rolled
  `Atomic.*`. The imports are vestigial. This means the suite exercises no kcas
  / lock-free MCAS at all, even when lavyek is enabled.
- The WAL path default in the source is `/tmp/lavyek_wal_<nb_domains>`, which is
  what you get for ad-hoc runs. When driven by the orchestrator the path comes
  in as the fourth argument instead (there is a `wal/` directory in the
  benchmark folder for exactly this).
