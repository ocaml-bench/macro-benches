# zarith

Zarith is OCaml's arbitrary-precision integer library, backed by GMP; each `Z.t` is a
custom block wrapping a GMP integer. This benchmark computes the digits of pi with the
unbounded spigot algorithm from Gibbons (2004), where every arithmetic step allocates a
fresh custom block and crosses into libgmp — so it allocates custom blocks faster than
anything else in the suite and leans on GMP stub calls and finalisation.

## Ladder

Input size = the **digit count** (the single required argument): more digits means
larger `Z.t` values and higher promotion pressure, not the same work N times. Wall scales
as ~digits² (`wall ≈ 1.07e-8 · N²` on the reference machine). Measured on 5.5.0, Ryzen 9
9950X:

| rung | digits | wall | gc% | max GC pause | promotion | RSS* |
|------|--------|------|-----|--------------|-----------|------|
| small   | 22 000  | 5.5s  | 19% | 40 ms  | 7%  | 9 MB  |
| default | 38 000  | 17s   | 18% | 100 ms | 10% | 9 MB  |
| large   | 106 000 | 123s  | 10% | 123 ms | 17% | 17 MB |
| huge    | 180 000 | 358s  | 8%  | 253 ms | 20% | 25 MB |

This scales **GC throughput and promotion pressure, not live-heap size**: even at 180k
digits the live heap is only ~11 MB, so fragmentation / large mark-sweep is not exercised
here (use owl for that). The rungs are complementary: gc% *falls* with size (more GMP
compute per allocation), so small/default are the most GC-throughput-sensitive; tail
pauses *grow* (40 → 253 ms), so large/huge are the most GC-latency-sensitive (major-GC
pacing, e.g. ocaml/ocaml#14796). The maj:min ratio is pinned at 0.50 throughout — the
character of the work is scale-invariant, only its intensity changes.

\* footprint from `/usr/bin/time` max-RSS. **Do not** use olly's `max_rss` here: under the
`re-25` ring it carries a ~258 MB fixed offset (the ring mapping) that swamps the real
footprint.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `zarith_pi` — the original fixed-digit-count bench (single baked-in digit count).

## Notes

- One of the few programs that also builds under OxCaml (along with menhir and decompress).
- The digit count is a required argument; running with no args prints usage and exits 2 —
  the arg is the problem size itself, not an iteration count.
