(* Lavyek key-value-store benchmark, adapted from upstream test.ml
   (https://github.com/tarides/lavyek) without the rocksdb/lmdb comparisons:
   nb_domains domains each run max_fibers Eio fibers doing put/get on a shared store.
   Args: nb_domains (4) max_fibers (100) nb (10_000_000) dbpath (/tmp/lavyek_wal_<nb_domains>) *)

open Eio

let () = Random.init 0
let nb_domains = try int_of_string Sys.argv.(1) with _ -> 4
let max_fibers = try int_of_string Sys.argv.(2) with _ -> 100
let nb = try int_of_string Sys.argv.(3) with _ -> 10_000_000
let dbpath =
  try Sys.argv.(4)
  with _ -> Printf.sprintf "/tmp/lavyek_wal_%d" nb_domains

let sync = false
let range = max 1 (100 / max_fibers)
let key_len = 24
let value_len = 100
let log10 n = int_of_float (ceil (log (float n) /. log 10.0))
let dynamic_key_len = log10 50_000_000
let key_prefix = String.make (max 0 (key_len - dynamic_key_len)) 'p'
let key_len = String.length key_prefix + dynamic_key_len

let redundancy = 1

(* Pin domain i to the same physical core (smt=0 thread, sorted by core id) on
   every run; otherwise the kernel migrates domains and wall times don't compare. *)
let physical_cpus =
  Processor.Topology.t
  |> List.filter (fun c -> c.Processor.Cpu.smt = 0)
  |> List.sort (fun a b -> compare a.Processor.Cpu.core b.Processor.Cpu.core)
  |> Array.of_list

let () =
  if Array.length physical_cpus < nb_domains then
    Printf.eprintf
      "lavyek_bench: warning: %d physical cores available but %d domains \
       requested; pinning will wrap modulo cores\n%!"
      (Array.length physical_cpus) nb_domains

let pin_to_domain_slot id_domain =
  let n = Array.length physical_cpus in
  if n > 0 then
    Processor.Affinity.set_cpus [ physical_cpus.(id_domain mod n) ]

let get_input i =
  assert (i >= 0);
  assert (i < nb);
  let key = string_of_int i in
  let key = key_prefix ^ key in
  let value = String.init value_len (fun j -> key.[j mod String.length key]) in
  (key, value)

let shuffle i = 50_000_017 * i mod nb
let other_shuffle i = 50_000_021 * i mod nb
let get_shuffled_input i = get_input (shuffle i)
let get_shuffled_input2 i = get_input (other_shuffle i)

let par_iter ~clock ~dmgr ~nb_domains ~sw ~get_input fn =
  let chunks_at = Atomic.make 0 in
  let start = Eio.Time.now clock in
  let latest_clock = Atomic.make start in
  let started = Atomic.make 0 in
  let previous_chunks_at = Atomic.make 0 in
  let stop = Atomic.make false in
  let domains =
    Array.init nb_domains @@ fun id_domain ->
    Fiber.fork_promise ~sw @@ fun () ->
    let fn () =
      pin_to_domain_slot id_domain;
      Atomic.incr started;
      while Atomic.get started < nb_domains do
        Fiber.yield ()
      done;
      Fiber.all @@ List.init max_fibers
      @@ fun _i () ->
      let rec loop () =
        if Atomic.get stop then raise Exit;
        let chunk_start = Atomic.fetch_and_add chunks_at range in
        let now = Eio.Time.now clock in
        let previous = Atomic.get latest_clock in
        if
          now -. previous > 1.0
          && Atomic.compare_and_set latest_clock previous now
        then (
          let prev = Atomic.get previous_chunks_at in
          Atomic.set previous_chunks_at chunk_start;
          Format.printf "%.2f\t%#i\t%#i@." (now -. start) chunk_start
            (chunk_start - prev));
        if chunk_start >= nb then ()
        else
          match
            let upper = min nb (chunk_start + range) in
            for i = chunk_start to upper - 1 do
              let key, value = get_input i in
              fn key value
            done
          with
          | exception err ->
              Format.printf "TEST ERROR: %s@." (Printexc.to_string err);
              Printexc.print_backtrace stderr;
              Atomic.set stop true;
              raise err
          | () -> loop ()
      in
      loop ()
    in
    if id_domain = 0 then fn () else Domain_manager.run dmgr fn
  in
  Array.iter Promise.await_exn domains

let run () =
  Eio_main.run @@ fun env ->
  let clock = Stdenv.clock env in
  let dmgr = Stdenv.domain_mgr env in
  let fs = Stdenv.fs env in
  let path = Path.(fs / dbpath) in
  Path.rmtree ~missing_ok:true path;
  let t_total_start = Unix.gettimeofday () in
  Eio.Switch.run (fun sw ->
    let db = Lavyek.open_out ~sw path in
    Format.printf "# Lavyek WRITE (%i domains, %i fibers, nb=%i)@."
      nb_domains max_fibers nb;
    par_iter ~sw ~clock ~dmgr ~nb_domains
      ~get_input:get_shuffled_input
      (fun key value -> Lavyek.put ~sync db key value);
    Lavyek.close db;
    Format.printf "@.@.";

    let db = Lavyek.open_out ~sw path in
    Format.printf "# Lavyek READ (%i domains, %i fibers, nb=%i)@."
      nb_domains max_fibers nb;
    par_iter ~sw ~clock ~dmgr ~nb_domains
      ~get_input:get_shuffled_input2
      (fun key value ->
        match Lavyek.find db ~key with
        | Some v when v = value -> ()
        | None -> failwith (Printf.sprintf "not found %S" key)
        | Some v ->
            failwith
              (Printf.sprintf "found invalid (%i, %i) %S: %S instead of %S"
                 (String.length v) (String.length value) key v value));
    Format.printf "@.@.";
    Lavyek.close db);
  let t_total_end = Unix.gettimeofday () in
  Printf.printf "Total: %.3f s (%d domains, %d fibers, %d ops)\n%!"
    (t_total_end -. t_total_start) nb_domains max_fibers nb;
  Path.rmtree ~missing_ok:true path

let () = run ()
