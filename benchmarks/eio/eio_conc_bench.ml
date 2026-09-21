(* Eio concurrency ladder. eio_fiber_stream is a throughput bench with a tiny
   constant live set; this scales the degree of concurrency instead.
   argv.1 = n_pairs producer/consumer fiber pairs, each on its own bounded
   Eio.Stream (one shared stream's O(n) waiter queue makes wall super-linear),
   so the working set grows ~linearly. argv.2 = items per fiber (20000), a fixed
   constant. 5.5.0: 3000 ~5.5s/0.69GB, 9000 ~16s/2.1GB, 21000 ~39s/5.1GB. *)

let n_pairs =
  if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 3000

let items_per =
  if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 20000

let producer stream id =
  for i = 1 to items_per do
    Eio.Stream.add stream (id, i, String.make 64 (Char.chr (65 + (id mod 26))))
  done

let consumer stream =
  for _ = 1 to items_per do
    let _ = Eio.Stream.take stream in
    ()
  done

let () =
  Eio_main.run @@ fun _env ->
  let streams = Array.init n_pairs (fun _ -> Eio.Stream.create 1024) in
  (* 2 * n_pairs fibers: even index = producer, odd = consumer, paired by p. *)
  Eio.Fiber.all
    (List.init (2 * n_pairs) (fun k () ->
         let p = k / 2 in
         if k mod 2 = 0 then producer streams.(p) p else consumer streams.(p)))
