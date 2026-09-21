(* merlin_bench.ml: in-process driver replicating the cram bench at
   duniverse/merlin/tests/test-dirs/server-tests/bench.t/run.t on the
   merlin-domains typer (Domain.spawn + Domain_msg, as ocamlmerlin_server's
   single mode). In-process because the merlin server daemonises, so olly would
   attach to the wrong PID. argv.1 = iterations over the 7 queries.
   Needs OCaml 5.5+: the branch's vendored typer targets the 5.5 ABI and trips
   an assertion in types.ml on 5.4 (expected, not a runtime regression). *)

open Merlin_kernel
module QP = Query_protocol

(* running-ng passes the ctxt.ml path via MERLIN_BENCH_CTXT; the fallback is for ad-hoc runs. *)
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

(* Existential wrapper so queries of different result types share one table. *)
type packed = Q : 'a QP.t -> packed

(* The 7 queries from bench.t/run.t. merlin positions are (line, col): line
   1-indexed, col 0-indexed bytes from the start of the line. *)
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
  (* Partial-typing target: the typer domain types up to `position`, hands back
     a partial pipeline and continues the rest in parallel with our query. *)
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
  (* Mpipeline needs a Local_store bound and a File_id cache active (as
     new_merlin does), else mocaml.ml:34 asserts. *)
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
