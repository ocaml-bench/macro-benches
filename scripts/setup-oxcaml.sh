#!/usr/bin/env bash
# Source patches that let the vendored tree compile with OxCaml as well as stock
# OCaml. Each one is plain OCaml that behaves identically on stock OCaml, so they
# are applied for every compiler. Called by setup-monorepo.sh ([35]-[45], [48]-[53], [55]-[62]) and, for
# infer's own checkouts that vendor-javalib-sawja.sh resets on every build, by
# vendor-javalib-sawja.sh ([46]-[47]). scripts/tests/oxcaml-repros.sh reproduces
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
# (a no-op once applied). Without "all", <old> must occur
# exactly once; a source in any other shape is an error, not a silent skip.
replace() {
  # An expanded file was patched before the expansion, which reprints it; the
  # manifest check covers its content.
  if [ -f duniverse/.ppx-expanded ] && grep -q "  $3\$" duniverse/.ppx-expanded; then
    echo "  [$1] $2: already applied (ppx-expanded)."
    return
  fi
  OX_OLD="$4" OX_NEW="$5" OX_ALL="${6:-}" python3 - "$1" "$2" "$3" <<'PYEOF'
import os, sys
num, label, path = sys.argv[1:]
old, new, every = os.environ["OX_OLD"], os.environ["OX_NEW"], os.environ["OX_ALL"] == "all"
s = open(path).read()
n = s.count(old)
# Applied when <new> is there and <old> is either gone or part of <new> (an insertion).
if new in s and (n == 0 or old in new):
    print(f"  [{num}] {label}: already applied.")
    sys.exit(0)
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

# variant <num> <label> <file> <old> <new>: for code against compiler-libs,
# whose API differs on OxCaml, so no one source compiles on both. Keeps <file>
# as <stem>.upstream.ml, writes <stem>.oxcaml.ml with <old> replaced by <new>,
# and adds the rule OxCaml's own vendored libraries use to pick one (it works
# from dune lang 1.0, which some of these projects declare).
variant() {
  local num=$1 label=$2 f=$3 d stem
  d=$(dirname "$f"); stem=$(basename "$f" .ml)
  if [ -f "$d/$stem.oxcaml.ml" ]; then
    echo "  [$num] $label: already applied."
    return
  fi
  mv "$f" "$d/$stem.upstream.ml"
  cp "$d/$stem.upstream.ml" "$d/$stem.oxcaml.ml"
  replace "$num" "$label" "$d/$stem.oxcaml.ml" "$4" "$5"
  cat >> "$d/dune" <<EOF

(rule
 (targets $stem.ml)
 (deps $stem.upstream.ml $stem.oxcaml.ml)
 (action
  (with-stdout-to
   %{targets}
   (system
    "case '%{ocaml_version}' in *+ox*) cat $stem.oxcaml.ml ;; *) cat $stem.upstream.ml ;; esac"))))
EOF
}

vendored() { [ -e "$1" ] || { echo "  [$2] $3: not vendored. Skipping."; return 1; }; }

duniverse_patches() {
  local B=duniverse/batteries-included/src

  if vendored duniverse/yojson/lib/write.ml 35 yojson; then
    for w in intlit floatlit stringlit; do
      replace 35 "yojson write_$w" duniverse/yojson/lib/write.ml \
        "let write_$w = Buffer.add_string" "let write_$w ob s = Buffer.add_string ob s"
    done
  fi

  if vendored duniverse/ocaml-extlib/src 36 extlib; then
    extlib_patches 36 duniverse/ocaml-extlib/src
  fi

  if vendored vendor/camlpdf 37 camlpdf; then
    replace 37 "camlpdf Pdfutil.mem" vendor/camlpdf/pdfutil.ml \
      "let mem = List.mem" "let mem x l = List.mem x l"
    replace 37 "camlpdf inline image buffer" vendor/camlpdf/pdfops.ml \
      'iter (Buffer.add_string b) ["BI\n"' 'iter (fun s -> Buffer.add_string b s) ["BI\n"'
  fi

  if vendored vendor/cpdf-source/cpdfyojson.ml 38 "cpdf bundled yojson"; then
    for w in intlit floatlit stringlit; do
      replace 38 "cpdf yojson write_$w" vendor/cpdf-source/cpdfyojson.ml \
        "let write_$w = Buffer.add_string" "let write_$w ob s = Buffer.add_string ob s" all
    done
  fi

  if vendored duniverse/rocq/clib/int.ml 39 rocq; then
    replace 39 "rocq Int.List.mem" duniverse/rocq/clib/int.ml \
      "  let mem = List.memq" "  let mem x l = List.memq x l"
  fi

  if vendored duniverse/lwt/src/unix/lwt_unix.cppo.ml 40 lwt; then
    local L=duniverse/lwt/src/unix/lwt_unix.cppo.ml
    replace 40 "lwt recv" "$L" "let do_recv = if Sys.win32 then Unix.recv else stub_recv in" \
      "let do_recv fd buf pos len fl = if Sys.win32 then Unix.recv fd buf pos len fl else stub_recv fd buf pos len fl in"
    replace 40 "lwt send" "$L" "let do_send = if Sys.win32 then Unix.send else stub_send in" \
      "let do_send fd buf pos len fl = if Sys.win32 then Unix.send fd buf pos len fl else stub_send fd buf pos len fl in"
    replace 40 "lwt recvfrom" "$L" "let do_recvfrom = if Sys.win32 then Unix.recvfrom else stub_recvfrom in" \
      "let do_recvfrom fd buf pos len fl = if Sys.win32 then Unix.recvfrom fd buf pos len fl else stub_recvfrom fd buf pos len fl in"
    replace 40 "lwt sendto" "$L" "let do_sendto = if Sys.win32 then Unix.sendto else stub_sendto in" \
      "let do_sendto fd buf pos len fl a = if Sys.win32 then Unix.sendto fd buf pos len fl a else stub_sendto fd buf pos len fl a in"
  fi

  if vendored duniverse/eio/lib_eio/core/cells.ml 41 eio; then
    replace 41 "eio Cells fetch_and_add" duniverse/eio/lib_eio/core/cells.ml \
      "    | True -> Atomic.fetch_and_add" "    | True -> fun t delta -> Atomic.fetch_and_add t delta"
  fi

  if vendored duniverse/repr/src/repr 42 repr; then
    replace 42 "repr random bool" duniverse/repr/src/repr/type_random.ml \
      "  | Bool -> stage R.bool" "  | Bool -> stage (fun s -> R.bool s)"
    replace 42 "repr binary bytes" duniverse/repr/src/repr/type_binary.ml \
      "    | Prim (Bytes _) -> stage Bytes.to_string" "    | Prim (Bytes _) -> stage (fun b -> Bytes.to_string b)"
    # The partial application here is what makes to_bin's continuation local.
    replace 42 "repr to_bin" duniverse/repr/src/repr/type_binary.ml \
      "      seq (Buffer.add_string buf);" "      seq (fun s -> Buffer.add_string buf s);"
  fi

  if vendored duniverse/devkit/ocamlnet_lite/netstring_tstring.ml 43 devkit; then
    local D=duniverse/devkit/ocamlnet_lite/netstring_tstring.ml
    replace 43 "devkit string ops sub" "$D" $'    sub = String.sub;\n    substring = String.sub;' \
      $'    sub = (fun s p l -> String.sub s p l);\n    substring = (fun s p l -> String.sub s p l);'
    replace 43 "devkit string ops blit/index" "$D" $'    blit_to_bytes = Bytes.blit_string;\n    index_from = String.index_from;' \
      $'    blit_to_bytes = (fun s p b q l -> Bytes.blit_string s p b q l);\n    index_from = (fun s p c -> String.index_from s p c);'
    replace 43 "devkit string ops rindex" "$D" "    rindex_from = String.rindex_from;" \
      "    rindex_from = (fun s p c -> String.rindex_from s p c);"
    replace 43 "devkit bytes ops blit" "$D" "    blit_to_bytes = Bytes.blit;" \
      "    blit_to_bytes = (fun s p b q l -> Bytes.blit s p b q l);"
  fi

  if vendored duniverse/iter/src/Iter.ml 44 iter; then
    # A later partial application fixes Iter.iter's own parameter mode as local.
    replace 44 "iter concat_str" duniverse/iter/src/Iter.ml \
      "  iter (Buffer.add_string b) seq;" "  iter (fun s -> Buffer.add_string b s) seq;"
  fi

  if vendored "$B" 45 batteries; then
    after 45 "batteries Bytes" "$B/batBytes.ml" $'include Bytes\n' \
      $'let blit a b c d e = blit a b c d e\nlet blit_string a b c d e = blit_string a b c d e\n'
    after 45 "batteries Queue" "$B/batQueue.ml" $'include Queue\n' \
      $'let iter f q = iter f q\nlet fold f acc q = fold f acc q\nlet transfer q1 q2 = transfer q1 q2\n'
    after 45 "batteries UTF8.Buf" "$B/batUTF8.ml" $'  include Buffer\n  type buf = t\n' \
      $'  let add_string b s = add_string b s\n'
    after 45 "batteries String" "$B/batString.ml" $'include String\n' \
      $'let blit a b c d e = blit a b c d e\nlet index_from s i c = index_from s i c\nlet rindex_from s i c = rindex_from s i c\nlet index_from_opt s i c = index_from_opt s i c\nlet rindex_from_opt s i c = rindex_from_opt s i c\n'
    replace 45 "batteries String.Cap blit" "$B/batString.ml" \
      "  let blit          = Bytes.blit" "  let blit a b c d e = Bytes.blit a b c d e"
    after 45 "batteries Buffer" "$B/batBuffer.ml" $'include Buffer\n' \
      $'let add_bytes b s = add_bytes b s\nlet add_string b s = add_string b s\nlet blit src srcoff dst dstoff len = blit src srcoff dst dstoff len\n'
    replace 45 "batteries List.mem" "$B/batList.ml" $'let mem = List.mem\nlet memq = List.memq' \
      $'let mem x l = List.mem x l\nlet memq x l = List.memq x l'
    replace 45 "batteries File.chmod" "$B/batFile.ml" "let chmod = Unix.chmod" "let chmod f p = Unix.chmod f p"
    # OxCaml removed these deprecated Gc functions; stock 5.x implements both as ().
    after 45 "batteries Gc eventlog" "$B/batGc.ml" $'include Gc\n' \
      $'let eventlog_pause () = ()\nlet eventlog_resume () = ()\n'
    after 45 "batteries Random.State" "$B/batRandom.ml" $'module State =\nstruct\n  include Random.State\n' \
      $'  let int t n = int t n\n  let full_int t n = full_int t n\n  let int_in_range t ~min ~max = int_in_range t ~min ~max\n  let int32 t n = int32 t n\n  let int32_in_range t ~min ~max = int32_in_range t ~min ~max\n  let nativeint t n = nativeint t n\n  let nativeint_in_range t ~min ~max = nativeint_in_range t ~min ~max\n  let int64 t n = int64 t n\n  let int64_in_range t ~min ~max = int64_in_range t ~min ~max\n  let float t f = float t f\n'
    after 45 "batteries Bigarray.Array0" "$B/batBigarray.ml" $'##V>=4.5##module Array0 = struct\n##V>=4.5##  include Bigarray.Array0\n' \
      $'##V>=4.5##  let set a v = set a v\n'
    after 45 "batteries Unix" "$B/batUnix.ml" $'include Unix\n' "$(cat <<'BATUNIX'
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

  # These intrinsics are unknown to OxCaml, which rejects an unrecognised
  # [@@builtin]; stock ignores the attribute, and both call the C stub.
  if vendored duniverse/ocaml_intrinsics_kernel/src 48 ocaml_intrinsics_kernel; then
    local I=duniverse/ocaml_intrinsics_kernel/src m f
    for m in int32 int64 nativeint; do
      for f in clz ctz; do
        replace 48 "intrinsics ${m}_${f}_nonzero" "$I/$m.ml" \
          "\"caml_${m}_${f}_nonzero_unboxed_to_untagged\""$'\n    [@@noalloc] [@@builtin]' \
          "\"caml_${m}_${f}_nonzero_unboxed_to_untagged\""$'\n    [@@noalloc]'
      done
    done
    for f in float.ml float.mli; do
      for m in min max; do
        replace 48 "intrinsics $f float64_$m" "$I/$f" \
          "\"caml_sse2_float64_$m\""$'\n  [@@noalloc] [@@builtin]' "\"caml_sse2_float64_$m\""$'\n  [@@noalloc]'
      done
    done
  fi

  if vendored duniverse/ocaml-ctypes/src/ctypes/ctypes_memory.ml 49 ctypes; then
    local k
    for k in Genarray Array1 Array2 Array3; do
      replace 49 "ctypes bigarray_kind $k" duniverse/ocaml-ctypes/src/ctypes/ctypes_memory.ml \
        "  | $k -> $k.kind" "  | $k -> fun ba -> $k.kind ba"
    done
  fi

  # Only in jsoo's [@@if oxcaml] code: OxCaml's Const_untagged_char carries an int.
  local J=duniverse/js_of_ocaml/compiler/lib/ocaml_compiler.ml
  if vendored "$J" 50 js_of_ocaml; then
    replace 50 "jsoo Const_untagged_char" "$J" \
      $'  | Const_base\n      ( Const_int8 i\n' $'  | Const_base\n      ( Const_untagged_char i\n      | Const_int8 i\n'
    replace 50 "jsoo Const_char" "$J" \
      $'  | Const_base (Const_char c) | Const_base (Const_untagged_char c) ->\n      Int (Targetint.of_int_exn (Char.code c))' \
      $'  | Const_base (Const_char c) -> Int (Targetint.of_int_exn (Char.code c))'
  fi

  if vendored duniverse/devkit/action.ml 51 devkit; then
    replace 51 "devkit random_int" duniverse/devkit/action.ml \
      $'  | None -> Random.int\n  | Some t -> Random.State.int t' \
      $'  | None -> (fun n -> Random.int n)\n  | Some t -> (fun n -> Random.State.int t n)'
    replace 51 "devkit reap_orphans" duniverse/devkit/httpev.ml \
      "Exn.catch (Unix.waitpid [Unix.WNOHANG]) 0" "Exn.catch (fun pid -> Unix.waitpid [Unix.WNOHANG] pid) 0"
    replace 51 "devkit Parallel waitpid" duniverse/devkit/parallel.ml \
      "Nix.restart (Unix.waitpid []) pid" "Nix.restart (fun pid -> Unix.waitpid [] pid) pid"
  fi

  # Its one caller applies it fully.
  if vendored duniverse/analyzer/src/util/std/gobRef.ml 52 goblint; then
    replace 52 "goblint GobRef.wrap" duniverse/analyzer/src/util/std/gobRef.ml \
      $'let wrap r x =\n  let x0 = !r in\n  r := x;\n  Fun.protect ~finally:(fun () -> r := x0)\n' \
      $'let wrap r x f =\n  let x0 = !r in\n  r := x;\n  Fun.protect ~finally:(fun () -> r := x0) f\n'
  fi

  # OxCaml's compilation unit names are Compilation_unit.t (as in OxCaml's own
  # vendored copy of this library).
  local RC=duniverse/ocaml-compiler-libs/src/read_cma/read_cma.ml
  if [ -e "$RC" ] || [ -e "${RC%.ml}.oxcaml.ml" ]; then
    variant 55 "ocaml-compiler-libs read_cma compunit_name" "$RC" \
      "let compunit_name Cmo_format.{ cu_name = Compunit name ; _ } = name" \
      "let compunit_name (cu : Cmo_format.compilation_unit_descr) = Compilation_unit.name_as_string cu.cu_name"
  fi

  # OxCaml's cmi_sign pairs the signature with a mode.
  local GEN=duniverse/base/shadow-stdlib/gen/gen.ml
  if [ -e "$GEN" ] || [ -e "${GEN%.ml}.oxcaml.ml" ]; then
    variant 56 "base shadow-stdlib gen cmi_sign" "$GEN" \
      "Printtyp.signature cmi.Cmi_format.cmi_sign" "Printtyp.signature (fst cmi.Cmi_format.cmi_sign)"
    # OxCaml moved Printtyp, Cmi_format and Subst out of compiler-libs.common
    # into compiler-libs.frontend, which stock lacks; bytecomp brings in the
    # right one on both.
    replace 57 "base shadow-stdlib gen compiler-libs" "${GEN%/*}/dune" \
      "(libraries str compiler-libs.common)" "(libraries str compiler-libs.common compiler-libs.bytecomp)"
  fi

  # base re-exports the stdlib's types from its .cmi; OxCaml's carry a kind
  # (`type t : k`), whose manifest must come after it. Never fires on stock.
  local MAP=duniverse/base/shadow-stdlib/gen/mapper.mll
  if vendored "$MAP" 53 base; then
    after 53 "base mapper kinded types" "$MAP" \
      $'  | "module Bigarray" _* { "" (* Don\'t deprecate it yet *) }\n' \
      $'  | "type " (params? as params) (id as id) " : " ([^ \'=\']* as kind) (_* as def)\n      { sprintf "type nonrec %s%s : %s = %sStdlib.%s%s\\n%s"\n          params id (String.trim kind)\n          params id\n          (if is_alias id || def = "" then "" else " " ^ def)\n          (match type_replacement id with\n           | Some replacement -> replace ~is_exn:false id replacement\n           | None -> deprecated_msg ~is_exn:false id) }\n\n'
  fi

  # OxCaml's 'a ref takes a value_or_null parameter, which an unannotated
  # `with type 'a ref :=` can't restate; the later `type 'a ref` shadows the
  # included one anyway. The Obj.magic arguments drop an ascription that the
  # stdlib's local parameters no longer satisfy.
  if vendored duniverse/base/src 58 base; then
    local BS=duniverse/base/src
    for f in import0.ml base.ml; do
      replace 58 "base $f ref" "$BS/$f" $'\n    with type \'a ref := \'a ref' ""
    done
    replace 58 "base Linked_queue0 iter" "$BS/linked_queue0.ml" \
      "Stdlib.Obj.magic (Stdlib.Queue.iter : ('a -> unit) -> 'a t -> unit)" "Stdlib.Obj.magic Stdlib.Queue.iter"
    replace 58 "base Linked_queue0 fold" "$BS/linked_queue0.ml" \
      "Stdlib.Obj.magic (Stdlib.Queue.fold : ('b -> 'a -> 'b) -> 'b -> 'a t -> 'b)" "Stdlib.Obj.magic Stdlib.Queue.fold"
    replace 58 "base Buffer length" "$BS/buffer.ml" \
      "(Stdlib.Obj.magic (Stdlib.Buffer.length : t -> int) : t -> int)" "(Stdlib.Obj.magic Stdlib.Buffer.length : t -> int)"
    replace 58 "base Buffer blit" "$BS/buffer.ml" \
      $'(Stdlib.Obj.magic\n     (Stdlib.Buffer.blit : Stdlib.Buffer.t -> int -> Bytes.t -> int -> int -> unit)\n    :' \
      $'(Stdlib.Obj.magic Stdlib.Buffer.blit\n    :'
    after 58 "base Buffer add_string/add_bytes" "$BS/buffer.ml" $'include Stdlib.Buffer\n' \
      $'\nlet add_string t s = Stdlib.Buffer.add_string t s\nlet add_bytes t b = Stdlib.Buffer.add_bytes t b\n'
  fi

  # OxCaml rejects %array_length on the abstract Permissioned.t (Jane Street's
  # oxcaml branch makes it a val too). The two anonymous modules only
  # type-check that S and Permissioned agree, which they no longer do.
  if vendored duniverse/core/core/src/array.ml 59 core; then
    local CA=duniverse/core/core/src/array.ml
    replace 59 "core Array.Permissioned length" "$CA" \
      "  external length : (('a, _) t[@local_opt]) -> int = \"%array_length\"" "  val length : (_, _) t -> int"
    replace 59 "core Array S/Permissioned checks" "$CA" \
      $'\nmodule _ (M : S) : sig\n  type (\'a, -\'perm) t_\n\n  include Permissioned with type (\'a, \'perm) t := (\'a, \'perm) t_\nend = struct\n  include M\n\n  type (\'a, -\'perm) t_ = \'a t\nend\n\nmodule _ (M : Permissioned) : sig\n  type \'a t_\n\n  include S with type \'a t := \'a t_\nend = struct\n  include M\n\n  type \'a t_ = (\'a, read_write) t\nend\n' ""
  fi

  if vendored duniverse/liquidsoap/src/lang/base 60 liquidsoap; then
    local LQ=duniverse/liquidsoap/src/lang/base
    replace 60 "liquidsoap Type_constraints.mem" "$LQ/types/type_constraints.ml" \
      "let mem = List.memq" "let mem x l = List.memq x l"
    replace 60 "liquidsoap kprint_string pager" "$LQ/lang_string.ml" \
      "f (print_string ~pager)" "f (fun s -> print_string ~pager s)"
    replace 60 "liquidsoap kprint_string buffer" "$LQ/lang_string.ml" \
      "f (Buffer.add_string ans);" "f (fun s -> Buffer.add_string ans s);"
  fi

  if vendored vendor/frama-c/src 61 frama-c; then
    local FC=vendor/frama-c/src
    replace 61 "frama-c Cmdline Queue.iter" "$FC/kernel_services/cmdline_parameters/cmdline.ml" \
      "(Pretty_utils.pp_iter Queue.iter " "(Pretty_utils.pp_iter (fun f q -> Queue.iter f q) "
    replace 61 "frama-c Parameter_builder mem" "$FC/kernel_services/cmdline_parameters/parameter_builder.ml" \
      "      let mem = List.mem"$'\n' "      let mem x l = List.mem x l"$'\n'
    replace 61 "frama-c Dotgraph add_label" "$FC/libraries/utils/dotgraph.ml" \
      "let add_label buffer = Buffer.add_string buffer.label" "let add_label buffer s = Buffer.add_string buffer.label s"
    replace 61 "frama-c Json save_buffer" "$FC/libraries/utils/json.mll" \
      "(dump (Buffer.add_string buffer) v" "(dump (fun s -> Buffer.add_string buffer s) v"
    replace 61 "frama-c Task cancel" "$FC/libraries/utils/task.ml" \
      "Array.iter (Queue.iter cancel) server.queue" "Array.iter (fun q -> Queue.iter cancel q) server.queue"
    replace 61 "frama-c Transfer_specification behaviors" "$FC/plugins/eva/engine/transfer_specification.ml" \
      "(List.exists (List.mem behavior) complete_behaviors)" "(List.exists (fun l -> List.mem behavior l) complete_behaviors)"
  fi

  # The list's constructors resolve through the expected type, which OxCaml
  # doesn't propagate back through `|>`.
  if vendored vendor/infer/infer/src 62 infer; then
    local IS=vendor/infer/infer/src
    for s in print_string prerr_string; do
      replace 62 "infer IStd.$s" "$IS/istd/IStd.ml" "fun _ -> Stdlib.$s" "fun _ s -> Stdlib.$s s"
    done
    replace 62 "infer taint dummy matchers" "$IS/pulse/PulseTaintOperations.ml" \
      $'  [ ClassAndMethodNames\n' $'  ( [ ClassAndMethodNames\n'
    replace 62 "infer taint dummy matchers type" "$IS/pulse/PulseTaintOperations.ml" \
      $'      ; exclude_names= None } ]\n  |> List.map ~f:dummy_matcher_of_procedure_matcher' \
      $'      ; exclude_names= None } ]\n    : Unit.procedure_matcher list )\n  |> List.map ~f:dummy_matcher_of_procedure_matcher'
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
  extlib_patches 46 "$src/extlib/src"
  # OxCaml records the pack prefix in the .cmi too, so interfaces and bytecode
  # must be compiled with -for-pack like the native code; stock OCaml accepts it.
  local rule
  for rule in .ml.cmo .mli.cmi; do
    replace 47 "javalib $rule -for-pack" "$src/javalib/src/Makefile" \
      "$rule:"$'\n\t$(OCAMLC) $(INCLUDE) -I ptrees -c $<' "$rule:"$'\n\t$(OCAMLC) $(INCLUDE) -I ptrees $(FOR_PACK) -c $<'
    replace 47 "sawja $rule -for-pack" "$src/sawja/src/Makefile" \
      "$rule:"$'\n\t$(OCAMLC) $(INCLUDE) -c $<' "$rule:"$'\n\t$(OCAMLC) $(INCLUDE) $(FOR_PACK) -c $<'
  done
}

case "${1:-}" in
  "") duniverse_patches ;;
  infer) infer_patches "${2:?usage: setup-oxcaml.sh infer <dir>}" ;;
  *) echo "usage: setup-oxcaml.sh [infer <dir>]" >&2; exit 2 ;;
esac
