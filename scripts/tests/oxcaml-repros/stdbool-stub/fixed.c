#include <caml/mlvalues.h>
#include <caml/misc.h>
#ifdef __bool_true_false_are_defined
#undef bool
#undef true
#undef false
#endif
typedef char bool;
value f(value u) { bool b = 1; return Val_int(b); }
