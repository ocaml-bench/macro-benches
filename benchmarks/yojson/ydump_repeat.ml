(* ydump_repeat: parse + compact-serialize a JSON document N times.
   argv.1 = iterations (default 10). argv.2 = an existing file to read, or an
   integer record count: a nested JSON array of that many ~125-byte records is
   generated in-process, so the ladder rungs need no input files. *)

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
