type (_, _) k = Gen : (('a, 'f, 'c) Bigarray.Genarray.t, ('a, 'f) Bigarray.kind) k
let kind : type b r. (b, r) k -> b -> r = function
  | Gen -> Bigarray.Genarray.kind
