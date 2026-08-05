# lavyek

Lavyek is a from-scratch multicore key-value store: Eio for fiber scheduling, io_uring
(via `eio_linux`) for its write-ahead log, hand-rolled `Atomic.*` structures for the
in-memory index. `lavyek_bench` runs a fixed 10M-op WRITE-then-READ load across a
configurable number of domains (cells `lavyek_kv_{1,2,4,8}d`), so the signal is
parallel scaling — the only multi-domain, io_uring, and CPU-affinity
(`ocaml-processor`) workload in the suite, with far more effect traffic than
`eio_fiber_stream`. When it ran (Ryzen 9 9950X, `re=22 md=8`): ~25/14/8/6s for
1/2/4/8 domains; the 4-domain cell is the calibrated target.

**Disabled — no ladder.** It is not in the default run set (`benchmarks: []`).

## Disabled

Lavyek lives in a private repo (`github.com/tarides/lavyek`), so `duniverse/lavyek/` is
absent and `setup-monorepo.sh` skips the clone. The benchmark definition stays in the
tree. Re-enable once you have repo access (uncomment the four cells in macro_base.yml's
`benchmarks:`); note the config string must then add `|re_par-22|md_par-8|pin_lavyek`,
and each domain pins itself to a physical core so multi-domain walls stay reproducible.
