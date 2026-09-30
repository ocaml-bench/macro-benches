#!/usr/bin/env bash
# Source patches that let the vendored tree compile with OxCaml as well as stock
# OCaml. Each one is plain OCaml that behaves identically on stock OCaml, so they
# are applied for every compiler. Called by setup-monorepo.sh ([32]-[42]) and, for
# infer's own checkouts that vendor-javalib-sawja.sh resets on every build, by
# vendor-javalib-sawja.sh ([43]-[44]). scripts/tests/oxcaml-repros.sh reproduces
# each class of incompatibility on its own.
#
# Usage: bash scripts/setup-oxcaml.sh            duniverse/ and vendor/
#        bash scripts/setup-oxcaml.sh infer <dir> extlib, javalib and sawja under <dir>
#
# Most entries eta-expand a stdlib function that OxCaml gives local (stack)
# parameters: re-exported curried (`let f = List.f`, `include List`, a record
# field, a partial application), its partial application is a local closure, so
# it no longer matches a signature that promises a global function.
set -euo pipefail
MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MONOREPO_DIR"

# replace <num> <label> <file> <old> <new> [all]: exact replacement, idempotent
# (a no-op once <new> is present). Without "all", <old> must occur
# exactly once; a source in any other shape is an error, not a silent skip.
replace() {
  OX_OLD="$4" OX_NEW="$5" OX_ALL="${6:-}" python3 - "$1" "$2" "$3" <<'PYEOF'
import os, sys
num, label, path = sys.argv[1:]
old, new, every = os.environ["OX_OLD"], os.environ["OX_NEW"], os.environ["OX_ALL"] == "all"
s = open(path).read()
if new in s:
    print(f"  [{num}] {label}: already applied.")
    sys.exit(0)
n = s.count(old)
if n == 0 or (n > 1 and not every):
    sys.exit(f"  [{num}] {label}: {path} not in the expected shape ({n} matches)")
open(path, "w").write(s.replace(old, new))
print(f"  [{num}] {label}: patched ({n}x).")
PYEOF
}

# after <num> <label> <file> <anchor> <text>: insert <text> right after the only
# occurrence of <anchor>; a no-op if it is already there.
after() {
  replace "$1" "$2" "$3" "$4" "$4$5"
}

vendored() { [ -e "$1" ] || { echo "  [$2] $3: not vendored. Skipping."; return 1; }; }

duniverse_patches() {
  local B=duniverse/batteries-included/src

  if vendored duniverse/yojson/lib/write.ml 32 yojson; then
    for w in intlit floatlit stringlit; do
      replace 32 "yojson write_$w" duniverse/yojson/lib/write.ml \
        "let write_$w = Buffer.add_string" "let write_$w ob s = Buffer.add_string ob s"
    done
  fi

  if vendored duniverse/ocaml-extlib/src 33 extlib; then
    extlib_patches 33 duniverse/ocaml-extlib/src
  fi

  if vendored vendor/camlpdf 34 camlpdf; then
    replace 34 "camlpdf Pdfutil.mem" vendor/camlpdf/pdfutil.ml \
      "let mem = List.mem" "let mem x l = List.mem x l"
    replace 34 "camlpdf inline image buffer" vendor/camlpdf/pdfops.ml \
      'iter (Buffer.add_string b) ["BI\n"' 'iter (fun s -> Buffer.add_string b s) ["BI\n"'
  fi

  if vendored vendor/cpdf-source/cpdfyojson.ml 35 "cpdf bundled yojson"; then
    for w in intlit floatlit stringlit; do
      replace 35 "cpdf yojson write_$w" vendor/cpdf-source/cpdfyojson.ml \
        "let write_$w = Buffer.add_string" "let write_$w ob s = Buffer.add_string ob s" all
    done
  fi

  if vendored duniverse/rocq/clib/int.ml 36 rocq; then
    replace 36 "rocq Int.List.mem" duniverse/rocq/clib/int.ml \
      "  let mem = List.memq" "  let mem x l = List.memq x l"
  fi

  if vendored duniverse/lwt/src/unix/lwt_unix.cppo.ml 37 lwt; then
    local L=duniverse/lwt/src/unix/lwt_unix.cppo.ml
    replace 37 "lwt recv" "$L" "let do_recv = if Sys.win32 then Unix.recv else stub_recv in" \
      "let do_recv fd buf pos len fl = if Sys.win32 then Unix.recv fd buf pos len fl else stub_recv fd buf pos len fl in"
    replace 37 "lwt send" "$L" "let do_send = if Sys.win32 then Unix.send else stub_send in" \
      "let do_send fd buf pos len fl = if Sys.win32 then Unix.send fd buf pos len fl else stub_send fd buf pos len fl in"
    replace 37 "lwt recvfrom" "$L" "let do_recvfrom = if Sys.win32 then Unix.recvfrom else stub_recvfrom in" \
      "let do_recvfrom fd buf pos len fl = if Sys.win32 then Unix.recvfrom fd buf pos len fl else stub_recvfrom fd buf pos len fl in"
    replace 37 "lwt sendto" "$L" "let do_sendto = if Sys.win32 then Unix.sendto else stub_sendto in" \
      "let do_sendto fd buf pos len fl a = if Sys.win32 then Unix.sendto fd buf pos len fl a else stub_sendto fd buf pos len fl a in"
  fi

  if vendored duniverse/eio/lib_eio/core/cells.ml 38 eio; then
    replace 38 "eio Cells fetch_and_add" duniverse/eio/lib_eio/core/cells.ml \
      "    | True -> Atomic.fetch_and_add" "    | True -> fun t delta -> Atomic.fetch_and_add t delta"
  fi

  if vendored duniverse/repr/src/repr 39 repr; then
    replace 39 "repr random bool" duniverse/repr/src/repr/type_random.ml \
      "  | Bool -> stage R.bool" "  | Bool -> stage (fun s -> R.bool s)"
    replace 39 "repr binary bytes" duniverse/repr/src/repr/type_binary.ml \
      "    | Prim (Bytes _) -> stage Bytes.to_string" "    | Prim (Bytes _) -> stage (fun b -> Bytes.to_string b)"
    # The partial application here is what makes to_bin's continuation local.
    replace 39 "repr to_bin" duniverse/repr/src/repr/type_binary.ml \
      "      seq (Buffer.add_string buf);" "      seq (fun s -> Buffer.add_string buf s);"
  fi

  if vendored duniverse/devkit/ocamlnet_lite/netstring_tstring.ml 40 devkit; then
    local D=duniverse/devkit/ocamlnet_lite/netstring_tstring.ml
    replace 40 "devkit string ops sub" "$D" $'    sub = String.sub;\n    substring = String.sub;' \
      $'    sub = (fun s p l -> String.sub s p l);\n    substring = (fun s p l -> String.sub s p l);'
    replace 40 "devkit string ops blit/index" "$D" $'    blit_to_bytes = Bytes.blit_string;\n    index_from = String.index_from;' \
      $'    blit_to_bytes = (fun s p b q l -> Bytes.blit_string s p b q l);\n    index_from = (fun s p c -> String.index_from s p c);'
    replace 40 "devkit string ops rindex" "$D" "    rindex_from = String.rindex_from;" \
      "    rindex_from = (fun s p c -> String.rindex_from s p c);"
    replace 40 "devkit bytes ops blit" "$D" "    blit_to_bytes = Bytes.blit;" \
      "    blit_to_bytes = (fun s p b q l -> Bytes.blit s p b q l);"
  fi

  if vendored duniverse/iter/src/Iter.ml 41 iter; then
    # A later partial application fixes Iter.iter's own parameter mode as local.
    replace 41 "iter concat_str" duniverse/iter/src/Iter.ml \
      "  iter (Buffer.add_string b) seq;" "  iter (fun s -> Buffer.add_string b s) seq;"
  fi

  if vendored "$B" 42 batteries; then
    after 42 "batteries Bytes" "$B/batBytes.ml" $'include Bytes\n' \
      $'let blit a b c d e = blit a b c d e\nlet blit_string a b c d e = blit_string a b c d e\n'
    after 42 "batteries Queue" "$B/batQueue.ml" $'include Queue\n' \
      $'let iter f q = iter f q\nlet fold f acc q = fold f acc q\nlet transfer q1 q2 = transfer q1 q2\n'
    after 42 "batteries UTF8.Buf" "$B/batUTF8.ml" $'  include Buffer\n  type buf = t\n' \
      $'  let add_string b s = add_string b s\n'
    after 42 "batteries String" "$B/batString.ml" $'include String\n' \
      $'let blit a b c d e = blit a b c d e\nlet index_from s i c = index_from s i c\nlet rindex_from s i c = rindex_from s i c\nlet index_from_opt s i c = index_from_opt s i c\nlet rindex_from_opt s i c = rindex_from_opt s i c\n'
    replace 42 "batteries String.Cap blit" "$B/batString.ml" \
      "  let blit          = Bytes.blit" "  let blit a b c d e = Bytes.blit a b c d e"
    after 42 "batteries Buffer" "$B/batBuffer.ml" $'include Buffer\n' \
      $'let add_bytes b s = add_bytes b s\nlet add_string b s = add_string b s\nlet blit src srcoff dst dstoff len = blit src srcoff dst dstoff len\n'
    replace 42 "batteries List.mem" "$B/batList.ml" $'let mem = List.mem\nlet memq = List.memq' \
      $'let mem x l = List.mem x l\nlet memq x l = List.memq x l'
    replace 42 "batteries File.chmod" "$B/batFile.ml" "let chmod = Unix.chmod" "let chmod f p = Unix.chmod f p"
    # OxCaml removed these deprecated Gc functions; stock 5.x implements both as ().
    after 42 "batteries Gc eventlog" "$B/batGc.ml" $'include Gc\n' \
      $'let eventlog_pause () = ()\nlet eventlog_resume () = ()\n'
    after 42 "batteries Random.State" "$B/batRandom.ml" $'module State =\nstruct\n  include Random.State\n' \
      $'  let int t n = int t n\n  let full_int t n = full_int t n\n  let int_in_range t ~min ~max = int_in_range t ~min ~max\n  let int32 t n = int32 t n\n  let int32_in_range t ~min ~max = int32_in_range t ~min ~max\n  let nativeint t n = nativeint t n\n  let nativeint_in_range t ~min ~max = nativeint_in_range t ~min ~max\n  let int64 t n = int64 t n\n  let int64_in_range t ~min ~max = int64_in_range t ~min ~max\n  let float t f = float t f\n'
    after 42 "batteries Bigarray.Array0" "$B/batBigarray.ml" $'##V>=4.5##module Array0 = struct\n##V>=4.5##  include Bigarray.Array0\n' \
      $'##V>=4.5##  let set a v = set a v\n'
    after 42 "batteries Unix" "$B/batUnix.ml" $'include Unix\n' "$(cat <<'BATUNIX'
let handle_unix_error f x = handle_unix_error f x
let accept ?cloexec a1 = accept ?cloexec a1
let access a0 a1 = access a0 a1
let chmod a0 a1 = chmod a0 a1
let chown a0 a1 a2 = chown a0 a1 a2
let create_process a0 a1 a2 a3 a4 = create_process a0 a1 a2 a3 a4
let create_process_env a0 a1 a2 a3 a4 a5 = create_process_env a0 a1 a2 a3 a4 a5
let dup ?cloexec a1 = dup ?cloexec a1
let dup2 ?cloexec a1 a2 = dup2 ?cloexec a1 a2
let execv a0 a1 = execv a0 a1
let execve a0 a1 a2 = execve a0 a1 a2
let execvp a0 a1 = execvp a0 a1
let execvpe a0 a1 a2 = execvpe a0 a1 a2
let getaddrinfo a0 a1 a2 = getaddrinfo a0 a1 a2
let getnameinfo a0 a1 = getnameinfo a0 a1
let getservbyname a0 a1 = getservbyname a0 a1
let initgroups a0 a1 = initgroups a0 a1
let lseek a0 a1 a2 = lseek a0 a1 a2
let mkdir a0 a1 = mkdir a0 a1
let mkfifo a0 a1 = mkfifo a0 a1
let pipe ?cloexec a1 = pipe ?cloexec a1
let putenv a0 a1 = putenv a0 a1
let read a0 a1 a2 a3 = read a0 a1 a2 a3
let recv a0 a1 a2 a3 a4 = recv a0 a1 a2 a3 a4
let recvfrom a0 a1 a2 a3 a4 = recvfrom a0 a1 a2 a3 a4
let rename a0 a1 = rename a0 a1
let send a0 a1 a2 a3 a4 = send a0 a1 a2 a3 a4
let send_substring a0 a1 a2 a3 a4 = send_substring a0 a1 a2 a3 a4
let sendto a0 a1 a2 a3 a4 a5 = sendto a0 a1 a2 a3 a4 a5
let sendto_substring a0 a1 a2 a3 a4 a5 = sendto_substring a0 a1 a2 a3 a4 a5
let single_write a0 a1 a2 a3 = single_write a0 a1 a2 a3
let single_write_substring a0 a1 a2 a3 = single_write_substring a0 a1 a2 a3
let socket ?cloexec a1 a2 a3 = socket ?cloexec a1 a2 a3
let socketpair ?cloexec a1 a2 a3 = socketpair ?cloexec a1 a2 a3
let truncate a0 a1 = truncate a0 a1
let utimes a0 a1 a2 = utimes a0 a1 a2
let waitpid a0 a1 = waitpid a0 a1
let write a0 a1 a2 a3 = write a0 a1 a2 a3
let write_substring a0 a1 a2 a3 = write_substring a0 a1 a2 a3
let link ?follow a1 a2 = link ?follow a1 a2
let symlink ?to_dir a1 a2 = symlink ?to_dir a1 a2
let read_bigarray a0 a1 a2 a3 = read_bigarray a0 a1 a2 a3
let write_bigarray a0 a1 a2 a3 = write_bigarray a0 a1 a2 a3
let single_write_bigarray a0 a1 a2 a3 = single_write_bigarray a0 a1 a2 a3
module LargeFile = struct
  include LargeFile
  let lseek a b c = lseek a b c
  let truncate a b = truncate a b
end
BATUNIX
)"$'\n'
  fi
}

# extlib's List/String re-export stdlib functions through `include`.
extlib_patches() {
  local num=$1 d=$2
  after "$num" "extlib List" "$d/extList.ml" $'include List\n' \
    $'\nlet mem x t = mem x t\nlet memq x t = memq x t\n'
  after "$num" "extlib String" "$d/extString.ml" $'include String\n' \
    $'\nlet blit a b c d e = blit a b c d e\nlet index_from a b c = index_from a b c\nlet index_from_opt a b c = index_from_opt a b c\nlet rindex_from a b c = rindex_from a b c\nlet rindex_from_opt a b c = rindex_from_opt a b c\n'
}

infer_patches() {
  local src=$1
  extlib_patches 43 "$src/extlib/src"
  # OxCaml records the pack prefix in the .cmi too, so interfaces and bytecode
  # must be compiled with -for-pack like the native code; stock OCaml accepts it.
  local rule
  for rule in .ml.cmo .mli.cmi; do
    replace 44 "javalib $rule -for-pack" "$src/javalib/src/Makefile" \
      "$rule:"$'\n\t$(OCAMLC) $(INCLUDE) -I ptrees -c $<' "$rule:"$'\n\t$(OCAMLC) $(INCLUDE) -I ptrees $(FOR_PACK) -c $<'
    replace 44 "sawja $rule -for-pack" "$src/sawja/src/Makefile" \
      "$rule:"$'\n\t$(OCAMLC) $(INCLUDE) -c $<' "$rule:"$'\n\t$(OCAMLC) $(INCLUDE) $(FOR_PACK) -c $<'
  done
}

case "${1:-}" in
  "") duniverse_patches ;;
  infer) infer_patches "${2:?usage: setup-oxcaml.sh infer <dir>}" ;;
  *) echo "usage: setup-oxcaml.sh [infer <dir>]" >&2; exit 2 ;;
esac
