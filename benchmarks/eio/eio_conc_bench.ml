(* Eio concurrency Knob-A ladder driver.

   The frozen eio_fiber_stream (eio_bench.ml) is a THROUGHPUT benchmark: a few
   fibers streaming a huge number of items through one shared bounded stream, so
   its live set is tiny (~9 MB) and constant — scaling its item count is pure
   repetition (Knob B). This driver scales the other axis, the one an effect
   scheduler exists for: the *degree of concurrency*.

   Knob A = n_pairs (Sys.argv.(1)): the number of independent producer/consumer
   fiber pairs, each pair communicating over its own bounded Eio.Stream. All
   2 * n_pairs fibers are alive at once, so the working set grows ~linearly with
   n_pairs — the parked fibers' effect continuations plus the in-flight data
   buffered across all n_pairs streams. Unlike a single shared stream (whose
   O(n) waiter queue makes wall blow up super-linearly under contention), giving
   each pair its own stream keeps scheduling ~linear, so wall tracks the working
   set. items_per (Sys.argv.(2), default 20000) is the fixed per-fiber work;
   it is a methodology constant, not the ladder axis.

   Measured on OCaml 5.5.0, Ryzen 9 9950X: n_pairs 3000 ~5.5s/0.69GB, 9000
   ~16s/2.1GB, 21000 ~39s/5.1GB (top_heap 84->619M words, promotion ~0.85 — the
   buffered/in-flight data is genuinely retained, so this is a live-set ladder). *)

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
