(* ydump_repeat: parse + compact-serialize a JSON file N times.
   Exercises JSON parsing, tree construction, serialization, and GC. *)

let () =
  let n = try int_of_string Sys.argv.(1) with _ -> 10 in
  let file = Sys.argv.(2) in
  let data = In_channel.with_open_bin file In_channel.input_all in
  Printf.printf "Input: %d bytes, %d iterations\n%!" (String.length data) n;
  for _ = 1 to n do
    let json = Yojson.Safe.from_string data in
    let _out = Yojson.Safe.to_string json in
    ()
  done;
  Printf.printf "Done\n%!"
