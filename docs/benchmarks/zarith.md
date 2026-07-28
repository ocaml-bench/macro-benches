# zarith

Zarith is OCaml's arbitrary-precision integer library, backed by GMP. Each
`Z.t` is a custom block wrapping a GMP integer. This benchmark computes the
digits of pi with a streaming spigot algorithm, which turns into a flood of
small `Z.t` allocations and GMP calls.

## What it runs

The program is `zarith_pi` (`benchmarks/zarith/zarith_pi.ml`), adapted from
Zarith's own test code. It implements the unbounded spigot algorithm from
Gibbons (2004) and prints pi one digit at a time. Every arithmetic step
(`+`, `*`, `/` on `Z.t`) allocates a fresh custom block holding a GMP
`mpz_t`.

The number of digits is the single command-line argument, and it is
required: the program prints a usage message and exits if it is not given
exactly one argument. The digit count comes from the runner configuration,
not from a default baked into the program; the suite exposes it as a
DaCapo-style size ladder (see "Size variants" below). The build script
copies the `.exe` out directly (no wrapper).

## What it stresses

- Custom-block allocation and finalisation. `Z.t` is a custom block with
  GMP-aware finalise, compare, hash, and marshal callbacks. This benchmark
  allocates them faster than anything else in the suite.
- GMP stub calls. Every arithmetic operation crosses into libgmp.
- Tail recursion. The core `digit` loop is written as a tail-recursive
  function, so it also leans on tail-call handling.
- The digit output goes through `Z.output` (Printf/Format), but that is not
  the hot part; the allocation churn is.

## Size variants (Knob-A ladder)

The digit count is a genuine working-set knob, not a repetition count: more
digits means larger `Z.t` values (more/bigger GMP custom blocks) and higher
promotion pressure, not just "the same work N times". Wall scales as ~digits²
(`wall ≈ 1.07e-8 · N²` on the Ryzen 9950X reference machine). The suite exposes
four sizes (running-ng programs `zarith_pi_{small,default,large,huge}`):

| rung | digits | wall | gc% | max GC pause | promotion | RSS* |
|------|--------|------|-----|--------------|-----------|------|
| small   | 22 000  | 5.5s  | 19% | 40 ms  | 7%  | 9 MB  |
| default | 38 000  | 17s   | 18% | 100 ms | 10% | 9 MB  |
| large   | 106 000 | 123s  | 10% | 123 ms | 17% | 17 MB |
| huge    | 180 000 | 358s  | 8%  | 253 ms | 20% | 25 MB |

\* footprint from `/usr/bin/time` max-RSS. **Do not** use olly's `max_rss` here:
under the `re-25` runtime_events ring it carries a ~258 MB fixed offset (the ring
mapping) that swamps the real footprint.

What the ladder does — and does *not* — cover:

- It scales **GC throughput and promotion pressure**, not live-heap size. Even at
  180k digits the live heap is only ~11 MB; this is an allocation-churn bench, not
  a large-heap one. Fragmentation / large mark-sweep behaviour is **not** exercised
  here (use owl or a large-live-set bench for that).
- The rungs are **complementary, not redundant**: gc% *falls* with size (more GMP
  mutator compute per allocation), so **small/default are the most GC-throughput-
  sensitive**; tail pauses *grow* with size (40 → 253 ms), so **large/huge are the
  most GC-latency-sensitive** (major-GC pacing, e.g. ocaml/ocaml#14796).
- The maj:min collection ratio is pinned at 0.50 across all sizes and allocation
  stays overwhelmingly major-heap (custom-block/GMP) throughout — the *character*
  of the work is scale-invariant; only its intensity and promotion pressure change.

## Reading the results

Per-rung gc% and pause profiles are in the table above; gc% is size-dependent, so
compare like-for-like rungs across runtimes. Collection counts are very high (the
mass of short-lived `Z.t` blocks) — on the order of 225k minor / 112k major at
`small`, rising to 4.8M / 2.4M at `huge`.

If this moves but a Bigarray benchmark like owl does not, suspect the
custom-block path specifically (zarith uses custom blocks, owl uses
Bigarray). If both move, it points at general FFI overhead.

## Notes

- One of the few programs that also builds under OxCaml (along with menhir
  and decompress).
- The digit count is a required argument; running the binary with no args
  just prints usage and exits 2. It does not follow the "iteration count"
  arg convention that owl, pplacer, and liq-video-frames use; here the arg
  is the problem size itself.
