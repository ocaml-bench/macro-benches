let iter f l = List.iter f l
let concat b l = iter (fun s -> Buffer.add_string b s) l
