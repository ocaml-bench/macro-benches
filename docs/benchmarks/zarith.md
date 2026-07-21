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
exactly one argument. The suite runs it for 15000 digits, so that count
comes from the runner configuration, not from a default baked into the
program. The build script copies the `.exe` out directly (no wrapper).

## What it stresses

- Custom-block allocation and finalisation. `Z.t` is a custom block with
  GMP-aware finalise, compare, hash, and marshal callbacks. This benchmark
  allocates them faster than anything else in the suite.
- GMP stub calls. Every arithmetic operation crosses into libgmp.
- Tail recursion. The core `digit` loop is written as a tail-recursive
  function, so it also leans on tail-call handling.
- The digit output goes through `Z.output` (Printf/Format), but that is not
  the hot part; the allocation churn is.

## Reading the results

Expect wall time around 8s with GC overhead near 27%, and very high
collection counts: on the order of 100k minor and 66k major collections,
the highest in the suite. That is the mass of short-lived `Z.t` blocks.

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
