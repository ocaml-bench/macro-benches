type ('a, 'b) result = ('a, 'b) Stdlib.result = Ok of 'a | Error of 'b
type ('a, 'b) either = ('a, 'b) Either.t = Left of 'a | Right of 'b
type 'a seq = 'a Seq.t
and 'a node = 'a Seq.node = Nil | Cons of 'a * 'a seq
type 'a ref = 'a Stdlib.ref = { mutable contents : 'a }
type 'a list = 'a Stdlib.List.t = [] | (::) of 'a * 'a list
