(* merlin_bench.ml — in-process driver replicating the cram bench at
   duniverse/merlin/tests/test-dirs/server-tests/bench.t/run.t.

   Exercises the merlin-domains feature: a single typer domain spawned
   alongside the main domain, with partial-typing + cancellation
   message-passing through Domain_msg. This is the same Domain.spawn
   dance ocamlmerlin_server.ml does in `single` and `server` mode, so
   we exercise the production code path.

   Why in-process and not via the merlin server: our framework
   attaches olly to the wrapper PID. The merlin server forks itself
   off into a daemon, so olly would attach to the wrong process. The
   single-mode path is what we replicate.

   Workload: 7 queries from the cram bench, replayed N times in a
   loop (Sys.argv.(1) iterations, default 1). Each iteration runs
   all 7 queries against the 51 319-line ctxt.ml. The two consecutive
   `case-analysis` queries at the same position test the typer cache
   and the partial-typing handoff.

   Runtime requirement: OCaml 5.5+ (e.g. d8bb46c). The merlin-domains
   branch ships its own copy of OCaml's typer at src/ocaml/typing/,
   targeted at the 5.5 ABI (OCaml_5_5_0 in merlin_config.ml). On
   earlier compilers (5.4.1, 5.3, ...) the vendored typer trips an
   assertion in types.ml because internal data-structure invariants
   differ. Running this benchmark against 5.4 produces a Fatal error
   inside the typer; that's expected, not a runtime regression. The
   running-ng macrobenchmarks_base.yml comment for macro-merlin
   documents this. *)

open Merlin_kernel
module QP = Query_protocol

(* The cram-bench input lives inside the merlin checkout; running-ng
   passes its absolute path via env so we don't have to guess at run
   time. The fallback is the conventional location for ad-hoc
   invocations. *)
let ctxt_path =
  match Sys.getenv_opt "MERLIN_BENCH_CTXT" with
  | Some p -> p
  | None ->
    let monorepo =
      Sys.getenv_opt "RUNNING_MACRO_MONOREPO_DIR"
      |> Option.value ~default:"."
    in
    Filename.concat monorepo
      "duniverse/merlin/tests/test-dirs/server-tests/bench.t/ctxt.ml"

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let b = Bytes.create n in
  really_input ic b 0 n;
  close_in ic;
  Bytes.unsafe_to_string b

(* Pack a Query_protocol.t at any result type into one existential
   so we can iterate the table uniformly. *)
type packed = Q : 'a QP.t -> packed

(* The 7 queries from tests/test-dirs/server-tests/bench.t/run.t.

   Each row carries:
     - a label (for logs)
     - a (line, col) pair for Mpipeline.get's ?position argument —
       this is the partial-typing target: the typer domain types up
       to this point, hands the partial pipeline back, and continues
       the rest in parallel with our query
     - the Query_protocol.t value, packed in an existential, with
       its own Msource.position arguments

   merlin's positions are (line, col): line is 1-indexed, col is
   0-indexed bytes-from-start-of-line. *)
let cram_queries : (string * (int * int) * packed) list =
  let mpos line col = `Logical (line, col) in
  [
    "construct@3:21", (3, 21),
      Q (QP.Construct (mpos 3 21, None, None));
    "complete-prefix@109:14", (109, 14),
      Q (QP.Complete_prefix ("fo", mpos 109 14, [], false, true));
    "complete-prefix@51152:12", (51152, 12),
      Q (QP.Complete_prefix ("xy", mpos 51152 12, [], false, true));
    "case-analysis@50796:25 (1)", (50796, 25),
      Q (QP.Case_analysis (mpos 50796 25, mpos 50796 25));
    "case-analysis@50796:25 (2)", (50796, 25),
      Q (QP.Case_analysis (mpos 50796 25, mpos 50796 25));
    "case-analysis@51318:43", (51318, 43),
      Q (QP.Case_analysis (mpos 51318 43, mpos 51318 43));
    "complete-prefix@51319:30", (51319, 30),
      Q (QP.Complete_prefix
           ("UnregistrationParams.B", mpos 51319 30, [], false, true));
  ]

let run_query shared config source (_name, position, Q query) =
  (* `position` here is the (line, col) for Mpipeline.get's
     partial-typing target: the typer domain types up to that point,
     hands a partial pipeline back, and continues the rest in
     parallel with our analysis call. *)
  let pipeline = Mpipeline.get ~position shared config source in
  ignore (Query_commands.dispatch pipeline query)

let () =
  let n =
    if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 1
  in
  Printf.eprintf "[merlin_bench] reading %s\n%!" ctxt_path;
  let text = read_file ctxt_path in
  let source = Msource.make text in
  Printf.eprintf "[merlin_bench] source loaded (%d bytes), spawning typer domain\n%!"
    (String.length text);

  let shared = Domain_msg.create () in
  let domain_typer = Domain.spawn @@ Mpipeline.domain_typer shared in

  let config = Mconfig.initial in
  (* Mpipeline expects a Local_store to be bound and a File_id cache
     to be active — the same setup new_merlin does before dispatching
     a query. Without these, mocaml.ml:34 asserts. *)
  File_id.with_cache @@ fun () ->
  let store = Mpipeline.Cache.get config in
  Local_store.open_store store;
  let cleanup () =
    Local_store.close_store store;
    Mpipeline.close_typer shared;
    Domain.join domain_typer
  in

  Printf.eprintf "[merlin_bench] running %d × %d queries\n%!"
    n (List.length cram_queries);
  (match
     for i = 1 to n do
       List.iter (run_query shared config source) cram_queries;
       if i mod 5 = 0 then
         Printf.eprintf "[merlin_bench]   iter %d/%d\n%!" i n
     done
   with
   | () -> cleanup ()
   | exception exn -> cleanup (); raise exn);
  Printf.eprintf "[merlin_bench] done\n%!"
