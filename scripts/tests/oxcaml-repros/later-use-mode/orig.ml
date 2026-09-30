type 'a t = ('a -> unit) -> unit
let iter f seq = seq f
let concat_str b seq = iter (Buffer.add_string b) seq
