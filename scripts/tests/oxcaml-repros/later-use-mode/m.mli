type 'a t = ('a -> unit) -> unit
val iter : ('a -> unit) -> 'a t -> unit
val concat_str : string t -> string
