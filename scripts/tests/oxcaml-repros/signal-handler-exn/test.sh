# Runs it: a timeout raised from a signal handler must be caught (exit 142);
# OxCaml makes it fatal (exit 2). fixed only sets a flag in the handler.
"$1/ocamlopt" -I +unix unix.cmxa "$2.ml" -o m.exe && { ./m.exe; [ $? -eq 142 ]; }
