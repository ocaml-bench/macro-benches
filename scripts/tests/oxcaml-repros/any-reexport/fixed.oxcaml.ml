type ('a : any, 'b : any) result = ('a, 'b) Stdlib.result = Ok of 'a | Error of 'b
type ('a : any, 'b : any) either = ('a, 'b) Either.t = Left of 'a | Right of 'b
type ('a : any) seq = 'a Seq.t
and ('a : any) node = 'a Seq.node = Nil | Cons of 'a * 'a seq
type ('a : any) ref = 'a Stdlib.ref = { mutable contents : 'a }
type ('a : any) list = 'a Stdlib.List.t = [] | (::) of 'a * 'a list
