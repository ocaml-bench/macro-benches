(* Workload for js_of_ocaml benchmark.
   Exercises many stdlib modules to create a non-trivial compilation target. *)

let () =
  (* Hashtbl + Gc stress *)
  let tbl = Hashtbl.create 10000 in
  for i = 0 to 99999 do
    Hashtbl.add tbl i (string_of_int i)
  done;
  let count = Hashtbl.fold (fun _ _ acc -> acc + 1) tbl 0 in
  Printf.printf "Hashtbl entries: %d\n" count;

  (* Buffer + String manipulation *)
  let buf = Buffer.create 1024 in
  for i = 0 to 9999 do
    Buffer.add_string buf (String.make 10 (Char.chr (65 + (i mod 26))));
    Buffer.add_char buf '\n'
  done;
  Printf.printf "Buffer length: %d\n" (Buffer.length buf);

  (* Map + Set *)
  let module IntMap = Map.Make(Int) in
  let module IntSet = Set.Make(Int) in
  let m = ref IntMap.empty in
  let s = ref IntSet.empty in
  for i = 0 to 49999 do
    m := IntMap.add i (float_of_int i) !m;
    s := IntSet.add (i * 7 mod 50000) !s
  done;
  Printf.printf "Map size: %d, Set size: %d\n"
    (IntMap.cardinal !m) (IntSet.cardinal !s);

  (* Array + sorting *)
  let arr = Array.init 100000 (fun i -> 100000 - i) in
  Array.sort compare arr;
  Printf.printf "Array sorted: first=%d last=%d\n" arr.(0) arr.(99999);

  (* List operations *)
  let lst = List.init 50000 (fun i -> i) in
  let filtered = List.filter (fun x -> x mod 3 = 0) lst in
  let mapped = List.map (fun x -> x * 2) filtered in
  Printf.printf "List operations: %d elements\n" (List.length mapped);

  (* Lazy + Seq *)
  let fibs = Seq.unfold (fun (a, b) ->
    if a > 1000000 then None
    else Some (a, (b, a + b))
  ) (0, 1) in
  let fib_list = List.of_seq fibs in
  Printf.printf "Fibonacci count: %d\n" (List.length fib_list);

  Printf.printf "Workload complete\n"
