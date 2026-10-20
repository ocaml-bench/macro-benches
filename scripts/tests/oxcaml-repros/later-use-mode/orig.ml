type 'a t = ('a -> unit) -> unit
let iter f seq = seq f
let concat_str seq =
  let b = Buffer.create 64 in
  iter (Buffer.add_string b) seq;
  Buffer.contents b
