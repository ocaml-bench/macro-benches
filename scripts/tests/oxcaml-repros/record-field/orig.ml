type 't ops = { blit_to_bytes : 't -> int -> Bytes.t -> int -> int -> unit }
let string_ops = { blit_to_bytes = Bytes.blit_string }
