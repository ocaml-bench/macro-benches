# Upstream bug: race in `merlin-domains` causes non-deterministic
# `Types.rev_log` assertion failure

**Status:** suspected race in the merlin-domains parallel-typer
implementation. Reproducible on the canonical workload at
`tests/test-dirs/server-tests/bench.t/` after a small number of
sequential queries. Filed against `ocaml/merlin#merlin-domains`
(commit `7f033f9352531e0179f5d3a1f0000bb1be740844`).

**Environment:**
- OCaml 5.5.0~beta1 (`d8bb46c39bf5fcafb513a8ba18e667d3f8c2600a`)
- Linux 6.8.0 x86_64, 8-core Intel Xeon E5-2667 v2 @ 3.30 GHz
- merlin-domains branch HEAD `7f033f9352531e0179f5d3a1f0000bb1be740844`
- macro-benches commit `7733c4d` (driver source)

## Symptom

```
Fatal error: exception
  File "duniverse/merlin/src/ocaml/typing/types.ml",
  line 924, characters 15-21: Assertion failed
```

The assertion is:

```ocaml
let rec rev_log accu = function
    Unchanged -> accu
  | Invalid -> assert false        (* line 924 — fires here *)
  | Change (ch, next) ->
      let d = !next in
      next := Invalid;
      rev_log (ch::accu) d
```

In short: the typer is asked to walk a section of its
type-environment trail that has already been marked `Invalid` by a
prior `backtrack`. That should never happen in single-threaded
operation; the new typer-domain in the merlin-domains branch makes
it possible.

## Repro (~30 lines, no merlin code)

The minimal driver replays the 7 queries from the cram bench
`tests/test-dirs/server-tests/bench.t/run.t` against `ctxt.ml` (the
51 319-line synthetic file shipped in that directory) in a loop. The
spawn pattern is exactly what `ocamlmerlin_server` does in `single`
mode.

```ocaml
(* merlin_bench.ml *)
open Merlin_kernel
module QP = Query_protocol
type packed = Q : 'a QP.t -> packed
let mpos l c = `Logical (l, c)

let queries = [
  (3, 21),       Q (QP.Construct (mpos 3 21, None, None));
  (109, 14),     Q (QP.Complete_prefix ("fo", mpos 109 14, [], false, true));
  (51152, 12),   Q (QP.Complete_prefix ("xy", mpos 51152 12, [], false, true));
  (50796, 25),   Q (QP.Case_analysis (mpos 50796 25, mpos 50796 25));
  (50796, 25),   Q (QP.Case_analysis (mpos 50796 25, mpos 50796 25));
  (51318, 43),   Q (QP.Case_analysis (mpos 51318 43, mpos 51318 43));
  (51319, 30),   Q (QP.Complete_prefix
                      ("UnregistrationParams.B", mpos 51319 30,
                       [], false, true));
]

let () =
  let n = if Array.length Sys.argv > 1
          then int_of_string Sys.argv.(1) else 1 in
  let text = (* read tests/.../ctxt.ml *) ... in
  let source = Msource.make text in
  let shared = Domain_msg.create () in
  let domain_typer = Domain.spawn @@ Mpipeline.domain_typer shared in
  let config = Mconfig.initial in
  File_id.with_cache @@ fun () ->
  let store = Mpipeline.Cache.get config in
  Local_store.open_store store;
  for _ = 1 to n do
    List.iter (fun (position, Q query) ->
      let pipeline = Mpipeline.get ~position shared config source in
      ignore (Query_commands.dispatch pipeline query)
    ) queries
  done;
  Local_store.close_store store;
  Mpipeline.close_typer shared;
  Domain.join domain_typer
```

(Full source is shipped at
[`benchmarks/merlin/merlin_bench.ml`](merlin_bench.ml) in this repo.)

Build with `dune build` (NOT `--profile release` — see
"Build-system snags" below).

## Reliability of the repro

The race fires non-deterministically. Same workload, same input,
same binary — different outcomes:

| | N=1 | N=2 | N=3 | N=4 | N=5 | N=7 | N=10 | N=20 |
|---|---|---|---|---|---|---|---|---|
| trial 1 | ok | **FAIL** | ok | ok | ok | **FAIL** | ok | **FAIL @ ~iter 11** |
| trial 2 | ok | ok | ok | **FAIL** | **FAIL** | **FAIL** | **FAIL** | — |
| trial 3 | ok | ok | **FAIL** | ok | ok | ok | — | — |

N=1 (one round of 7 queries) has not been observed to fail in our
sample, but every N≥2 has produced at least one failure. This is
consistent with a race that has a small per-query window and is not
correlated with workload size beyond crossing the "more than one
round" threshold.

## Why we suspect it's the typer-domain handoff and not an OCaml ABI issue

We initially observed this on OCaml 5.4.1 (where the merlin-domains
branch fails essentially every run) and assumed it was an ABI
mismatch — the `src/ocaml/typing/` snapshot in the branch is from
OCaml 5.3 (`upstream/ocaml_503/`), so being miscompiled against
newer compilers seemed like a plausible cause.

But the same assertion fires on d8bb46c (5.5-beta) at the same line,
just less frequently. This indicates the bug is in merlin-domains,
not in the OCaml-version mismatch. The version mismatch only changes
the trigger rate, not whether the bug exists.

The PR description for [#1890 "Typer domain"](https://github.com/ocaml/merlin/pull/1890)
also flags this directly:

> Removal of laziness, which is incompatible with concurrency.
> However, this introduces new bugs as some previously deferred
> computations now run eagerly:
> - The `local_store` scope must be carefully extended.
> - At least one exception is currently not properly caught.

The most likely root cause is in this area — the `Local_store`
scope around the typer-domain's call to `Mpipeline.get` does not
fully isolate the trail in `Types`, so a backtrack on one domain
invalidates trail tail nodes that the other domain is concurrently
walking.

## Build-system snags found while writing this repro

These are not part of the bug, but came up during reproduction and
may need fixing for anyone trying the branch:

1. **`gen_config.ml` only enumerates OCaml versions up to 5.3.** Any
   compiler from 5.4+ produces a tag (e.g. ``\`OCaml_5_5_0``) that's
   not in the polymorphic-variant type, so the build fails before
   reaching merlin code. Two-line patch:

   ```diff
   -  | `OCaml_5_3_0  ] = %s
   +  | `OCaml_5_3_0  | `OCaml_5_4_0  | `OCaml_5_5_0  | `OCaml_5_6_0
   +  ] = %s
   ```

2. **`parser_raw.ml` references `MenhirLib.StaticVersion.require_20201216`,
   but the bundled `menhirLib.ml` provides `require_20250912`.** dune's
   `release` profile uses the checked-in `parser_raw.ml`; the dev
   profile lets menhir regenerate it from `parser_raw.mly`. In
   release the build fails. Workaround: build without `--profile
   release`. Proper fix: regenerate `parser_raw.ml` from the current
   bundled menhir and commit.

## Suggested next step for whoever picks this up

The clean repro at N=2 is the smallest version. Run with
`OCAMLRUNPARAM=v=0x40` (or attach a debugger / runtime_events) to
capture the order of `snapshot` / `backtrack` events on each domain.
The expected pattern is "main domain backtracks past a point the
typer domain is still walking" — once you see that, the fix is
either:

- Tighten the `Local_store` scope so each domain has its own
  `Types.trail` ref, OR
- Add explicit synchronization on `backtrack` so the typer can't
  invalidate trail nodes the main domain is reading.

The `Mpipeline.get` / `domain_typer` message-passing in
`src/kernel/mpipeline.ml` is the place to add the fix.
