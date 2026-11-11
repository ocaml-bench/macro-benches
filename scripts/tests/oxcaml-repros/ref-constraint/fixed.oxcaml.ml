module Shadow = struct include Stdlib end
include (Shadow : module type of struct include Shadow end)
type ('a : any) ref = 'a Stdlib.ref = { mutable contents : 'a }
