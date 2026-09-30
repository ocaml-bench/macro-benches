type 'a t = ('a -> unit) -> unit
let iter f seq = seq f
let concat_str b seq = iter (fun s -> Buffer.add_string b s) seq
