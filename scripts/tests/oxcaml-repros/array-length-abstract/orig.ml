module M : sig
  type t
  external length : t -> int = "%array_length"
end = struct
  type t = int array
  external length : t -> int = "%array_length"
end
let n (x : M.t) = M.length x
