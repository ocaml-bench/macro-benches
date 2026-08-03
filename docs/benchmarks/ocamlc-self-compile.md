# ocamlc-self-compile

`ocamlc` is itself a real OCaml program, so this benchmark measures the
runtime-under-test executing a genuine compiler workload: its own `ocamlc`
(bytecode) compiling one big generated source file (20 classic OCaml-testsuite
programs wrapped in modules and replicated `OCAMLC_SELF_COMPILE_REPLICAS` times,
default 30). Bytecode (not `ocamlopt`) is used so the same passes run on every
variant — cross-variant deltas reflect the runtime, not flambda doing extra work.
It stresses short-lived AST allocation, the typer's `Hashtbl` hash-consing
(`TypeHash`, not ephemerons), `Marshal` for the `.cmi`/`.cmo`, and the `Bigarray`
emit buffer.

## Ladder

**This workload has no size ladder** — scaling REPLICAS is shape-invariant: the
JSOO numeric code builds a *monotonic* heap, so more replicas give proportionally
more of an identical GC pattern (promotion pinned ~0.11, major-GC count pinned ~13)
— a bigger heap, not a new regime. The compiler tool's size ladder lives on the
**uucp companion** instead ([ocamlc-compile-uucp.md](ocamlc-compile-uucp.md)),
whose actively-collected Unicode tables *do* scale the major-GC work. The two
bracket the collector by character:

| | `ocamlc_self_compile` | `ocamlc_compile_uucp` |
|---|---|---|
| input | JSOO numeric programs × REPLICAS | the uucp Unicode library |
| heap | large, **monotonic** | small, **collected** |
| major GC | barely runs (~13) | **active** (~154+) |
| gc% | ~40% | ~17% |

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `ocamlc_self_compile` — the compute/allocation-character fixed point (REPLICAS=30,
  ~3s on this machine; tune with `OCAMLC_SELF_COMPILE_REPLICAS`). Minor-GC-heavy,
  holds a big monotonic live set, ends with a bulk `Marshal`.

## Notes

Builds nothing through dune. The build hardlinks the real `ocamlc.opt` to a
uniquely-named binary (running-ng's process filter rejects anything named `ocamlc`,
which would break runtime-events attach) and pins `OCAMLLIB` (some builds resolve the
stdlib relative to `argv[0]`).
