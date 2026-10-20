module Shadow = struct include Stdlib end
include (Shadow : module type of struct include Shadow end
           with type 'a ref := 'a ref)
type 'a ref = 'a Stdlib.ref = { mutable contents : 'a }
