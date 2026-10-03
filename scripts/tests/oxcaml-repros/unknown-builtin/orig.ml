external clz : (int32[@unboxed]) -> (int[@untagged])
  = "caml_int32_clz" "caml_int32_clz_nonzero_unboxed_to_untagged"
  [@@noalloc] [@@builtin]
