type 't ops = { blit_to_bytes : 't -> int -> Bytes.t -> int -> int -> unit }
let string_ops = { blit_to_bytes = (fun s p b q l -> Bytes.blit_string s p b q l) }
