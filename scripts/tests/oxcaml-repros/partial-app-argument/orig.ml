let iter f l = List.iter f l
let concat b l = iter (Buffer.add_string b) l
