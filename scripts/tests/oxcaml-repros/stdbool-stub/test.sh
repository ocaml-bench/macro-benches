# A C stub that defines its own bool (apron's ap_config.h), compiled with the
# compiler's C flags; fixed is patch 54.
cp "$2.c" stub.c && "$1/ocamlopt" -c stub.c
