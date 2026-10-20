module M : sig
  type t
  val length : t -> int
end = struct
  type t = int array
  external length : t -> int = "%array_length"
end
let n (x : M.t) = M.length x
