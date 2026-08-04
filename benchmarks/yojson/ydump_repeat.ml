(* ydump_repeat: parse + compact-serialize a JSON document N times.
   Exercises JSON parsing, tree construction, serialization, and GC.

   Two knobs:
     argv.1 = iteration count (repetition; default 10).
     argv.2 = the document. If it names an existing file, that file is read
              (legacy behaviour, e.g. sample.json). Otherwise it is parsed as
              an integer RECORD COUNT and a JSON document of that many records
              is generated in-process (input size, working-set size) — so the ladder
              rungs need no vendored/generated files, just a count argument.

   The generated document is a JSON array of records shaped like
     {"id":i,"name":"item_i","value":i.j,"tags":["alpha","beta","gamma"],
      "active":bool,"nested":{"x":..,"y":..}}
   (~125 bytes each), which builds a realistically nested Yojson tree. *)

let generate_json records =
  let b = Buffer.create (records * 128) in
  Buffer.add_char b '[' ;
  for i = 0 to records - 1 do
    if i > 0 then Buffer.add_char b ',' ;
    Buffer.add_string b
      (Printf.sprintf
         "{\"id\":%d,\"name\":\"item_%d\",\"value\":%d.%d,\"tags\":[\"alpha\",\"beta\",\"gamma\"],\"active\":%s,\"nested\":{\"x\":%d,\"y\":%d}}"
         i i i (i mod 97) (if i mod 2 = 0 then "false" else "true") (i * 3) (i * 7))
  done ;
  Buffer.add_char b ']' ;
  Buffer.contents b

let () =
  let n = try int_of_string Sys.argv.(1) with _ -> 10 in
  let arg2 = Sys.argv.(2) in
  let data =
    if Sys.file_exists arg2 then
      In_channel.with_open_bin arg2 In_channel.input_all
    else generate_json (int_of_string arg2)
  in
  Printf.printf "Input: %d bytes, %d iterations\n%!" (String.length data) n;
  for _ = 1 to n do
    let json = Yojson.Safe.from_string data in
    let _out = Yojson.Safe.to_string json in
    ()
  done;
  Printf.printf "Done\n%!"
