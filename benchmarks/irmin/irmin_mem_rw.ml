(* irmin_mem_rw: read/write benchmark for Irmin in-memory store.
   Adapted from sandmark for irmin 3.x API. *)
open Lwt.Infix
open Printf

module Store = Irmin_mem.KV.Make (Irmin.Contents.String)

let info () =
  let date = Int64.of_float (Unix.gettimeofday ()) in
  Store.Info.v ~author:"BENCH" ~message:"benchmark" date

let path key = [ "root"; key ]

let write_loop store n =
  let rec aux i =
    if i >= n then Lwt.return_unit
    else
      let key = sprintf "key-%d" i in
      let value = sprintf "value-%d-%s" i (String.make 100 'x') in
      Store.set_exn ~info store (path key) value >>= fun () ->
      aux (i + 1)
  in
  aux 0

let read_loop store n =
  let rec aux i found =
    if i >= n then Lwt.return found
    else
      let key = sprintf "key-%d" i in
      Store.get store (path key) >>= fun _v ->
      aux (i + 1) (found + 1)
  in
  aux 0 0

let mixed_rw store n read_pct total_ops =
  let rec aux i reads writes =
    if i >= total_ops then Lwt.return (reads, writes)
    else
      let is_read = (i mod 100) < read_pct in
      let key = sprintf "key-%d" (i mod n) in
      if is_read then
        Store.get store (path key) >>= fun _v ->
        aux (i + 1) (reads + 1) writes
      else
        let value = sprintf "value-%d-%s" i (String.make 100 'y') in
        Store.set_exn ~info store (path key) value >>= fun () ->
        aux (i + 1) reads (writes + 1)
  in
  aux 0 0 0

let () =
  let n_keys, n_ops, read_pct, total =
    match Sys.argv with
    | [| _; nk; no; rp; t |] ->
      (int_of_string nk, int_of_string no, int_of_string rp, int_of_string t)
    | _ ->
      eprintf "Usage: %s <n_keys> <n_ops> <read_pct> <total_ops>\n" Sys.argv.(0);
      exit 1
  in
  Lwt_main.run begin
    let config = Irmin_mem.config () in
    Store.Repo.v config >>= fun repo ->
    Store.main repo >>= fun store ->

    (* Phase 1: Write n_keys entries *)
    let t0 = Unix.gettimeofday () in
    write_loop store n_keys >>= fun () ->
    let t1 = Unix.gettimeofday () in
    printf "Write phase: %d keys in %.3fs\n%!" n_keys (t1 -. t0);

    (* Phase 2: Read all entries *)
    read_loop store n_keys >>= fun found ->
    let t2 = Unix.gettimeofday () in
    printf "Read phase: %d/%d found in %.3fs\n%!" found n_keys (t2 -. t1);

    (* Phase 3: Mixed read/write *)
    mixed_rw store n_keys read_pct total >>= fun (reads, writes) ->
    let t3 = Unix.gettimeofday () in
    printf "Mixed phase (%d%% read): %d reads, %d writes in %.3fs\n%!"
      read_pct reads writes (t3 -. t2);

    printf "Total: %.3fs\n%!" (t3 -. t0);
    Lwt.return_unit
  end
