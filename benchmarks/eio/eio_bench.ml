(* Eio concurrent fiber benchmark.
   Stresses the OCaml 5 effect-based scheduler and GC with:
   - Many concurrent fibers producing/consuming data
   - Stream-based communication between fibers
   - Repeated allocation and GC pressure from fiber switching *)

let n_producers = 4
let n_consumers = 4
let items_per_producer = 5_000_000

let producer stream id =
  for i = 1 to items_per_producer do
    Eio.Stream.add stream (id, i, String.make 64 (Char.chr (65 + (id mod 26))))
  done

let consumer stream total =
  let count = ref 0 in
  while !count < total do
    let _id, _i, _data = Eio.Stream.take stream in
    incr count
  done;
  !count

let run_bench () =
  Eio_main.run @@ fun env ->
  let _domain_mgr = Eio.Stdenv.domain_mgr env in
  let stream = Eio.Stream.create 1024 in
  let total_items = n_producers * items_per_producer in
  let items_per_consumer = total_items / n_consumers in

  let t0 = Unix.gettimeofday () in

  Eio.Fiber.both
    (fun () ->
      Eio.Fiber.all (List.init n_producers (fun id () ->
        producer stream id)))
    (fun () ->
      let counts = ref [] in
      Eio.Fiber.all (List.init n_consumers (fun _id () ->
        let c = consumer stream items_per_consumer in
        counts := c :: !counts));
      let total = List.fold_left (+) 0 !counts in
      let t1 = Unix.gettimeofday () in
      Printf.printf "Processed %d items in %.3fs (%d producers, %d consumers)\n%!"
        total (t1 -. t0) n_producers n_consumers)

let () = run_bench ()
