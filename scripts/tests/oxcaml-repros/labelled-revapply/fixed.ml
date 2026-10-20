module U = struct type t = A of { x : int } end
let map l ~f = List.map f l
let f (_ : U.t) = ()
let _ = ([ A { x = 1 } ] : U.t list) |> map ~f
