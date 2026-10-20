let iter q ~f =
  let caml_iter : ('a -> unit) -> 'a Queue.t -> unit =
    Obj.magic (Queue.iter : ('a -> unit) -> 'a Queue.t -> unit)
  in
  caml_iter f q
