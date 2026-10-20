#include <caml/mlvalues.h>
#include <caml/misc.h>
typedef char bool;
value f(value u) { bool b = 1; return Val_int(b); }
