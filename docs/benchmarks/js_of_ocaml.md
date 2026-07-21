# js_of_ocaml

js_of_ocaml (jsoo) is a compiler that translates OCaml bytecode into JavaScript. This
benchmark runs it on the runtime-under-test's own `ocamlc.byte` and times how long the
translation takes.

## What it runs

One process: `js_of_ocaml.exe` (built from the vendored source under
`duniverse/js_of_ocaml/`) compiling the `ocamlc.byte` that ships in the switch being
tested. The command is effectively:

```
js_of_ocaml.exe <switch>/bin/ocamlc.byte -o <scratch>/out.js
```

`ocamlc.byte` is about 3.5 MB of bytecode and produces roughly 2.3 MB of JavaScript.
The output goes to a per-run scratch directory that is cleaned up afterward.

Using the runtime's own `ocamlc.byte` is convenient: it is a real, non-trivial
program, and each switch ships its own bytecode-magic-matched copy, so the workload is
naturally per-runtime with no hand-built input.

## What it stresses

Like the other compiler-throughput benchmarks, this is minor-GC-heavy and leans on
small-block allocation. The jsoo-specific parts:

- Bytecode parsing (`Parse_bytecode`): reading the `.byte` file, decoding
  instructions, constants, and debug info.
- SSA / IR construction and dataflow analysis: jsoo's intermediate representation is
  SSA, and building it stresses pointer-heavy structures (control-flow graph, def-use
  chains).
- Optimisation passes (dead-code elimination, inlining, escape analysis), each walking
  the program graph.
- JavaScript code generation, which is string-builder heavy.

jsoo also resolves runtime stubs through Findlib at run time, which is why the wrapper
sets `OCAMLPATH` and `OCAMLFIND_CONF` (see below).

## Reading the results

On 5.4.1 baseline, expect wall time around 7-9s, GC overhead around 33%, roughly
340 MB RSS, and on the order of 2260 minor / 28 major collections.

If this moves together with `ocamlc_self_compile`, suspect the minor-allocator fast
path (both are heavy on small-block allocation). If jsoo moves on its own, look at the
Findlib runtime, jsoo's IR construction, or OCaml's compiler-libs (which jsoo uses for
bytecode parsing). Flambda-built jsoo variants are expected to be slower per run
because they do more compiler work, which is a compile-time tax separate from any
runtime-perf signal.

## Notes

Two vendoring pins matter here, both handled by `scripts/setup-monorepo.sh`:

- jsoo is vendored from the `ocaml-5.6` branch, not the 6.2.0 release. The release
  hard-rejects OCaml 5.5+ with an assertion; the branch relaxes the bound to below 5.7,
  which covers the 5.4.1 / 5.5-beta / trunk targets in this suite.
- cmdliner is pinned to 2.1.0 (not the 1.3.0 the lockfile would give), because jsoo's
  command-line layer uses `Cmdliner.Arg.Completion`, which arrived in cmdliner 2.0.

The wrapper writes a sibling findlib config with absolute paths. The opam-installed
`findlib.conf` uses paths relative to the current directory, so running jsoo from any
directory other than the switch's `lib/` would fail with `No_such_package(stdlib)`.
The absolute-path config pointed at by `OCAMLFIND_CONF` makes it work regardless of
the working directory.
