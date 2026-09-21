#!/usr/bin/env bash
# Full setup of the macro-benches monorepo: populate duniverse/ and vendor/,
# apply the source patches, generate rocq's config + dunestrap files, smoke-build.
#
# Usage: bash scripts/setup-monorepo.sh
# Env:   TOOLS_SWITCH (default running-ng-tools): opam switch with dune + ocamlfind
#        SKIP_TEST_BUILD=1: skip the [9/9] smoke build
# Needs opam 2.3+ and libgmp-dev, libevent-dev, libcurl4-openssl-dev,
# libpcre3-dev, zlib1g-dev.
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MONOREPO_DIR"

source "$MONOREPO_DIR/scripts/lib-sources.sh"

if [[ -x /usr/local/bin/opam ]]; then
  _OPAM=/usr/local/bin/opam
else
  _OPAM="$(command -v opam || true)"
fi
if [ -z "${_OPAM:-}" ]; then
  echo "ERROR: opam not found (no executable /usr/local/bin/opam, none on PATH)." >&2
  exit 1
fi
TOOLS_SWITCH="${TOOLS_SWITCH:-running-ng-tools}"

# Take the tools switch's own environment rather than the caller's: bytecode
# linking resolves C stubs through the inherited CAML_LD_LIBRARY_PATH, so a
# shell pointed at a benchmark switch makes rocq's bytecode targets fail with
#   The external function caml_unix_sigwait is not available
# The switch's ld.conf alone is not enough (it omits lib/stublibs), hence `opam env`.
_tools_env="$("$_OPAM" env --switch="$TOOLS_SWITCH" --set-switch 2>/dev/null || true)"
if [ -z "$_tools_env" ]; then
  echo "ERROR: cannot read the environment of opam switch '$TOOLS_SWITCH'." >&2
  echo "       It must exist before setup runs. Create it, e.g.:" >&2
  echo "         opam switch create $TOOLS_SWITCH ocaml-base-compiler.5.4.0" >&2
  echo "       or point setup at an existing switch with TOOLS_SWITCH=<name>." >&2
  exit 1
fi
eval "$_tools_env"
unset _tools_env

TOOLS_PREFIX="$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")"
TOOLS_BIN="$TOOLS_PREFIX/bin"

echo "=== Macro-benches monorepo setup ==="
echo "Monorepo dir: $MONOREPO_DIR"
echo "Tools switch: $TOOLS_SWITCH ($TOOLS_BIN)"
echo ""

echo "[1/9] Ensuring tools switch has opam-monorepo + zarith..."
"$_OPAM" install --switch "$TOOLS_SWITCH" --yes opam-monorepo zarith dune ocamlfind
echo ""

echo "[2/9] Pulling vendored sources (opam monorepo pull)..."
if [ -d duniverse ] && [ "$(ls duniverse/ | wc -l)" -gt 0 ]; then
  echo "  duniverse/ already populated ($(ls duniverse/ | wc -l) packages). Skipping."
  echo "  To re-pull, remove duniverse/ first."
else
  OPAMSWITCH="$TOOLS_SWITCH" "$_OPAM" monorepo pull --lockfile=macro-benches.opam.locked
fi
echo ""

echo "[2.1/9] Vendoring merlin (pinned)..."
clone_pinned merlin duniverse/merlin
# The merlin-domains branch only enumerates OCaml versions up to 5.3, so 5.4+
# fail to compile; extend the variant.
if [ -f duniverse/merlin/src/config/gen_config.ml ] && \
   ! grep -q "OCaml_5_4_0" duniverse/merlin/src/config/gen_config.ml; then
  echo "  Patching merlin gen_config.ml for OCaml >= 5.4..."
  python3 - <<'PY'
import re
p = "duniverse/merlin/src/config/gen_config.ml"
s = open(p).read()
old = "`OCaml_5_3_0  ] = %s"
new = "`OCaml_5_3_0  | `OCaml_5_4_0  | `OCaml_5_5_0  | `OCaml_5_6_0\n  ] = %s"
assert old in s, "expected pattern not found in gen_config.ml"
open(p, "w").write(s.replace(old, new, 1))
PY
fi
echo ""

# Work around an OCaml 5.6-trunk typechecker crash (`Fatal error: exception
# Ctype.Unify(_)` in type_newtype) by inlining `map_chain` into its two callers
# in dolmen's base.ml; functionally identical.
echo "[2.2.5/9] Patching dolmen base.ml for OCaml 5.6 trunk typechecker bug..."
if [ -f duniverse/dolmen/src/typecheck/base.ml ] && \
   ! grep -q "map_chain_inlined" duniverse/dolmen/src/typecheck/base.ml; then
  python3 - <<'PY'
p = "duniverse/dolmen/src/typecheck/base.ml"
s = open(p).read()
inlined = """  let map_chain_inlined mk args =
    let rec aux mk = function
      | [] -> assert false
      | [_] -> []
      | x :: ((y :: _) as r) -> mk x y :: aux mk r
    in
    match aux mk args with
    | [] -> assert false
    | [x] -> x
    | l -> Type.T._and l
  in
"""
for old, new_call in [
    ("""let term_app_chain
    (type env) (type term)
    (module Type : Tff_intf.S with type env = env and type T.t = term)
    ?(check=(fun _ _ -> ())) env symbol mk =
  make_chain (module Type) env symbol (fun ast l ->
      check ast l;
      let l' = List.map (Type.parse_term env) l in
      map_chain (module Type) mk l'
    )""",
     "map_chain_inlined mk l'"),
    ("""let term_app_chain_ast
    (type env) (type term)
    (module Type : Tff_intf.S with type env = env and type T.t = term)
    ?(check=(fun _ _ -> ())) env symbol mk =
  make_chain (module Type) env symbol (fun ast l ->
      check ast l;
      let l' = List.map (Type.parse_term env) l in
      map_chain (module Type) (mk ast) l'
    )""",
     "map_chain_inlined (mk ast) l'"),
]:
    assert old in s, f"expected pattern not found in {p}:\n{old[:80]}..."
    header, body = old.split("symbol mk =\n  make_chain", 1)
    new = (header + "symbol mk =\n" + inlined +
           "  make_chain" +
           body.replace("map_chain (module Type) mk l'", new_call)
               .replace("map_chain (module Type) (mk ast) l'", new_call))
    s = s.replace(old, new, 1)
open(p, "w").write(s)
print("  Patched dolmen base.ml.")
PY
else
  echo "  Already patched (or file missing). Skipping."
fi
echo ""

# Released js_of_ocaml rejects OCaml >= 5.5; the pin is a master commit (sources.yml).
echo "[2.2/9] Vendoring js_of_ocaml (pinned)..."
clone_pinned js_of_ocaml duniverse/js_of_ocaml

# jsoo needs Cmdliner.Arg.Completion (2.x); the lock pins 1.3.0.
echo "[2.3/9] Vendoring cmdliner v2.1.1..."
if [ -d duniverse/cmdliner ] && \
   grep -qE "^version: \"2\." duniverse/cmdliner/cmdliner.opam 2>/dev/null; then
  echo "  duniverse/cmdliner/ already at >= 2.x. Skipping."
else
  # Upstream cmdliner has no dune files, so use the dune-universe 2.1.1+dune
  # build; its opam `version:` satisfies the skip-check above.
  rm -rf duniverse/cmdliner
  mkdir -p duniverse/cmdliner
  _cmdliner_url="$(src_field cmdliner-dune url)"
  _cmdliner_tbz="$(mktemp -d)/cmdliner.tbz"
  curl -fsSL "$_cmdliner_url" -o "$_cmdliner_tbz"
  # --no-same-owner: as root, tar restores the archive's uid/gid, which fails
  # with EPERM on a root-squashed NFS export (FreeBSD CI). Both tars accept the
  # long form; `-o` means different things to each.
  tar --no-same-owner -xf "$_cmdliner_tbz" -C duniverse/cmdliner --strip-components=1
  rm -f "$_cmdliner_tbz"
  echo "  Fetched cmdliner $(src_field cmdliner-dune version) (dune-universe overlay)."
fi
echo ""

# lavyek lives in a private repo (github.com/tarides/lavyek), so it is never
# cloned or built. To re-enable: uncomment this block, re-add lavyek_bench.exe
# to the [9/9] smoke build, and uncomment the lavyek cells in running-ng's
# macro_base.yml + smoke_macro.yml. `(dirs src)` skips upstream's `test` exe
# (links ahrocksdb + lmdb).
echo "[2.4/9] Vendoring lavyek + multicore deps... SKIPPED (private repo)."
# _clone_if_missing() {
#   local url="$1" dir="$2" branch="$3"
#   if [ -d "duniverse/$dir" ] && [ -f "duniverse/$dir/dune-project" ]; then
#     echo "  duniverse/$dir/ already populated. Skipping."
#   else
#     rm -rf "duniverse/$dir"
#     git clone --depth 1 -b "$branch" "$url" "duniverse/$dir"
#     rm -rf "duniverse/$dir/.git"
#     echo "  Cloned $dir."
#   fi
# }
# _clone_if_missing https://github.com/tarides/lavyek.git              lavyek               master
# _clone_if_missing https://github.com/ocaml-multicore/kcas.git        kcas                 main
# _clone_if_missing https://github.com/ocaml-multicore/backoff.git     backoff              main
# _clone_if_missing https://github.com/ocaml-multicore/multicore-magic.git multicore-magic  main
# _clone_if_missing https://github.com/ocaml-multicore/thread-table.git    thread-table     main
# _clone_if_missing https://github.com/ocaml-multicore/domain-local-timeout.git domain-local-timeout main
# _clone_if_missing https://github.com/ocaml-ppx/ppx_deriving_yojson.git ppx_deriving_yojson master
# _clone_if_missing https://github.com/haesbaert/ocaml-processor.git    processor            main
# echo "(dirs src)" > duniverse/lavyek/dune
echo ""

# The switch dune binaries (3.22.1) cannot parse the `lang dune 3.23`
# dune-project the lock's dune pulls; lower it to 3.21.
echo "[3/9] Patching duniverse/dune_/dune-project (lang dune 3.2x → 3.21)..."
if grep -qE 'lang dune 3\.2[0-9]' duniverse/dune_/dune-project 2>/dev/null && \
   ! grep -q 'lang dune 3.21' duniverse/dune_/dune-project 2>/dev/null; then
  sed_i -E 's/lang dune 3\.2[0-9]+/lang dune 3.21/' duniverse/dune_/dune-project
  rm -rf duniverse/dune_/test
  echo "  Patched ($(head -1 duniverse/dune_/dune-project))."
else
  echo "  Already patched (or version differs). Skipping."
fi
echo ""

# dune 3.24 deleted the `coq` language extension, so `(using coq 0.8)` fails to
# parse and takes every build in the workspace down:
#   Error: Extension coq was deleted in the 3.24 version of the dune language
# Both declarations are dead here: rocq generates its theory rules via
# tools/dune_rule_gen, and the `(coq (flags))` field is only in the dev profile.
echo "[3b/9] Patching duniverse/rocq for dune >= 3.24 (dropping dead coq extension)..."
_rocq_patched=0
if grep -qE '^\(using coq [0-9.]+\)' duniverse/rocq/dune-project 2>/dev/null; then
  # Also drop the comment that exists only to explain the declaration.
  sed_i -E '/^; We need this for when we use the dune\.disabled files instead of our rule_gen$/d; /^\(using coq [0-9.]+\)$/d' \
    duniverse/rocq/dune-project
  _rocq_patched=1
fi
if grep -qE '^ *\(coq \(flags' duniverse/rocq/dune 2>/dev/null; then
  python3 - <<'PYEOF'
import pathlib, re
p = pathlib.Path("duniverse/rocq/dune")
s = p.read_text()
# `(dev (flags ...)\n  (coq (flags ...)))` -> `(dev (flags ...))`
s2 = re.sub(r"(\(dev\s+\(flags[^\n]*?)\)\n\s*\(coq \(flags[^\n]*?\)\)\)\n",
            r"\1))\n", s)
if s2 == s:
    raise SystemExit("rocq dune: dev-profile coq field not matched -- patch me")
p.write_text(s2)
PYEOF
  _rocq_patched=1
fi
if [ "$_rocq_patched" = "1" ]; then
  echo "  Patched (removed (using coq ...) and/or the dev-profile coq flags)."
else
  echo "  Already patched. Skipping."
fi
unset _rocq_patched
echo ""

# Patch 20: rocq toplevel/dune: force the memtrace-free init variant. dune's
# (select) picks the memtrace clause as soon as memtrace is anywhere in the
# workspace (decompress vendors it), but the rocq bootstrap's gen_rules.exe
# resolves rocq-runtime.toplevel through findlib on $OCAMLPATH, where the
# vendored memtrace is never installed:
#   [gen_rules] Fatal error: findlib error: memtrace not found
echo "[3c/9] Patching duniverse/rocq/toplevel/dune (force memtrace-free init)..."
ROCQ_TOP_DUNE="duniverse/rocq/toplevel/dune"
if [ -f "$ROCQ_TOP_DUNE" ] && grep -qF "(memtrace -> memtrace_init.memtrace.ml)" "$ROCQ_TOP_DUNE" 2>/dev/null; then
  python3 - <<'PYEOF'
import pathlib, re
p = pathlib.Path("duniverse/rocq/toplevel/dune")
s = p.read_text()
# (select memtrace_init.ml from
#  (memtrace -> memtrace_init.memtrace.ml)
#  (!memtrace -> memtrace_init.default.ml))
# -> (select memtrace_init.ml from
#     (-> memtrace_init.default.ml))
s2 = re.sub(
    r"\(select\s+memtrace_init\.ml\s+from\s+"
    r"\(memtrace\s*->\s*memtrace_init\.memtrace\.ml\)\s+"
    r"\(!memtrace\s*->\s*memtrace_init\.default\.ml\)\)",
    "(select memtrace_init.ml from\n   (-> memtrace_init.default.ml))",
    s, count=1)
if s2 == s:
    raise SystemExit("rocq toplevel/dune: memtrace select not matched -- patch me")
p.write_text(s2)
PYEOF
  echo "  [20] rocq toplevel/dune: forced memtrace-free init (default select clause)."
elif [ -f "$ROCQ_TOP_DUNE" ]; then
  echo "  [20] rocq toplevel/dune: already patched (or select absent). Skipping."
else
  echo "  [20] rocq toplevel/dune: not vendored. Skipping."
fi
echo ""

echo "[4/9] Vendoring cpdf + camlpdf..."
if [ -d vendor/camlpdf ] && [ -d vendor/cpdf-source ]; then
  echo "  vendor/camlpdf and vendor/cpdf-source already exist. Skipping."
else
  bash scripts/vendor-cpdf.sh
fi
echo ""

echo "[4b/9] Vendoring processor..."
if [ -d vendor/processor ]; then
  echo "  vendor/processor already exists. Skipping."
else
  # Per-thread CPU affinity for infer's analysis domains. A plain dune library,
  # so it drops straight into the workspace.
  rm -rf vendor/processor
  mkdir -p vendor/processor
  _proc_url="$(src_field processor url)"
  _proc_tgz="$(mktemp -d)/processor.tgz"
  curl -fsSL "${_proc_url}" -o "${_proc_tgz}"
  _proc_want="$(src_field processor md5)"
  _proc_got="$(checksum "${_proc_tgz}")"
  if [ -n "${_proc_want}" ] && [ "${_proc_want}" != "${_proc_got}" ]; then
    echo "ERROR: processor tarball md5 ${_proc_got}, expected ${_proc_want}" >&2
    exit 1
  fi
  tar --no-same-owner -xzf "${_proc_tgz}" -C vendor/processor --strip-components=1
  rm -f "${_proc_tgz}"
  # bin/ declares a public executable, which patches 2, 8 and 9 exist to remove
  # from vendored code; drop it instead.
  rm -rf vendor/processor/test vendor/processor/bench \
         vendor/processor/bin vendor/processor/other
  echo "  Fetched processor $(src_field processor version)."
fi
echo ""

echo "[5/9] Vendoring zarith..."
if ls duniverse/[Zz]arith*/zarith.opam >/dev/null 2>&1; then
  echo "  zarith already in duniverse (dune-universe +dune version). Skipping manual vendor."
elif [ -d vendor/zarith ]; then
  echo "  vendor/zarith already exists. Skipping."
else
  bash scripts/vendor-coq.sh
  rm -rf vendor/rocq
  echo "  Removed vendor/rocq (using duniverse/rocq instead)."
fi
echo ""

echo "[6/9] Vendoring devkit deps (libevent + ocurl)..."
if [ -d vendor/libevent ]; then
  echo "  vendor/libevent already exists. Skipping."
else
  bash scripts/vendor-devkit-deps.sh
  if [ -d duniverse/ocurl ] && [ -d vendor/ocurl ]; then
    rm -rf vendor/ocurl
    echo "  Removed vendor/ocurl (using duniverse/ocurl instead)."
  fi
fi
for pkg in ocurl menhir; do
  if [ -d "duniverse/$pkg" ] && [ -d "vendor/$pkg" ]; then
    rm -rf "vendor/$pkg"
    echo "  Removed vendor/$pkg (using duniverse/$pkg instead)."
  fi
done
echo ""

echo "[6b/9] Vendoring pplacer + mcl..."
bash scripts/vendor-pplacer.sh
echo ""

echo "[6c/9] Vendoring frama-c (kernel + EVA)..."
bash scripts/vendor-frama-c.sh
echo ""

echo "[7/9] Applying vendored source patches..."

# Patch 1: alt-ergo ppx_blob paths (workspace-root-relative)
THEORIES_ML="duniverse/alt-ergo/src/lib/util/theories.ml"
if grep -q '\[%blob "src/preludes/' "$THEORIES_ML" 2>/dev/null; then
  sed_i 's|\[%blob "src/preludes/|\[%blob "duniverse/alt-ergo/src/preludes/|g' "$THEORIES_ML"
  echo "  [1] alt-ergo ppx_blob paths: patched."
else
  echo "  [1] alt-ergo ppx_blob paths: already patched."
fi

# Patch 2: alt-ergo public_name removal from Main_text executable
ALT_ERGO_DUNE="duniverse/alt-ergo/src/bin/text/dune"
if grep -q '(public_name alt-ergo)' "$ALT_ERGO_DUNE" 2>/dev/null; then
  # Rewrite the whole file: sed is too fragile for nested s-expressions.
  cat > "$ALT_ERGO_DUNE" << 'DUNE_EOF'
(executable
  (name gen_link_flags)
  (libraries unix fmt)
  (modules gen_link_flags))
(rule
 (with-stdout-to link_flags.dune
  (run ./gen_link_flags.exe %{env:LINK_MODE=dynamic} %{ocaml-config:system})))
(executable
  (name Main_text)
  (libraries alt_ergo_common)
  (link_flags (:standard (:include link_flags.dune)))
  (modules Main_text))
DUNE_EOF
  echo "  [2] alt-ergo dune: rewritten (removed public_name/package/promote)."
else
  echo "  [2] alt-ergo dune: already patched."
fi

echo "  [3] dune_ version: done in step 3."

# Patch 4: ppxlib 5.6 support (replace the lockfile's ppxlib with a pinned commit)
echo "  [4] ppxlib 5.6 support (Ast_506):"
clone_pinned ppxlib duniverse/ppxlib

# Patch 5: lwt 5.6 support (replace the lockfile's lwt with a pinned commit)
echo "  [5] lwt 5.6 support (socketaddr.h):"
clone_pinned lwt duniverse/lwt

# Patch 6: devkit lwt 6.x compat; only needed once lwt >= 6.1.1 adds the
# virtual method `id` to Lwt_engine.abstract.
DEVKIT_LWT="duniverse/devkit/lwt_engines.ml"
if grep -q 'method virtual id' duniverse/lwt/src/unix/lwt_engine.mli 2>/dev/null; then
  if grep -q 'Engine_id__libevent' "$DEVKIT_LWT" 2>/dev/null; then
    echo "  [6] devkit lwt 6.x compat: already patched."
  else
    insert_after "$DEVKIT_LWT" 'libevent-based engine for lwt' \
      'type Lwt_engine.engine_id += Engine_id__libevent'
    insert_after "$DEVKIT_LWT" 'inherit Lwt_engine.abstract' \
      '  method id = Engine_id__libevent'
    echo "  [6] devkit lwt 6.x compat: patched."
  fi
else
  echo "  [6] devkit lwt 6.x compat: not needed (lwt < 6.1.1)."
fi

# Patch 7: libevent label fix (~persist and ~signal)
LIBEVENT_ML="vendor/libevent/libevent.ml"
if grep -q '~persist' "$LIBEVENT_ML" 2>/dev/null; then
  echo "  [7] libevent labels: already patched."
else
  sed_i 's/^let set base event fd etype persist/let set base event fd etype ~persist/' "$LIBEVENT_ML"
  sed_i 's/^let set_timer base event persist/let set_timer base event ~persist/' "$LIBEVENT_ML"
  sed_i 's/^let set_signal base event signal persist/let set_signal base event ~signal ~persist/' "$LIBEVENT_ML"
  echo "  [7] libevent labels: patched."
fi

# Patch 8: js_of_ocaml public_name removal (executable stanza only, not the
# install stanzas)
JSOO_DUNE="duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/dune"
if [ -f "$JSOO_DUNE" ] && grep -q '(public_name js_of_ocaml)' "$JSOO_DUNE" 2>/dev/null; then
  # Match on content, not line number: upstream reordered these fields and a
  # line-anchored sed silently became a no-op that still reported success.
  delete_first_match "$JSOO_DUNE" '^ [(]public_name js_of_ocaml[)]$'
  delete_first_match "$JSOO_DUNE" '^ [(]package js_of_ocaml-compiler[)]$'
  echo "  [8] jsoo public_name: removed from executable stanza."
elif [ -f "$JSOO_DUNE" ]; then
  echo "  [8] jsoo public_name: already removed."
else
  echo "  [8] jsoo: not vendored. Skipping."
fi

# Patch 9: ocamlformat public_name removal (only from executable stanza)
OCFMT_DUNE="duniverse/ocamlformat/bin/ocamlformat/dune"
if [ -f "$OCFMT_DUNE" ] && grep -q '(public_name ocamlformat)' "$OCFMT_DUNE" 2>/dev/null; then
  delete_first_match "$OCFMT_DUNE" '[(]public_name ocamlformat[)]'
  delete_first_match "$OCFMT_DUNE" '^ [(]package ocamlformat[)]$'
  echo "  [9] ocamlformat public_name: removed."
elif [ -f "$OCFMT_DUNE" ]; then
  echo "  [9] ocamlformat public_name: already removed."
else
  echo "  [9] ocamlformat: not vendored. Skipping."
fi

# Patch 10: owl C bug: std_gaussian_rvs called with arguments but takes none
OWL_EXPONPOW="duniverse/owl/src/owl/stats/owl_stats_dist_exponpow.c"
if [ -f "$OWL_EXPONPOW" ] && grep -q 'std_gaussian_rvs (a' "$OWL_EXPONPOW" 2>/dev/null; then
  sed_i 's/std_gaussian_rvs (a \/ sqrt (2.0))/gaussian_rvs (0, a \/ sqrt (2.0))/' "$OWL_EXPONPOW"
  sed_i 's/std_gaussian_rvs (B)/gaussian_rvs (0, B)/' "$OWL_EXPONPOW"
  echo "  [10] owl std_gaussian_rvs: patched (upstream C bug)."
elif [ -f "$OWL_EXPONPOW" ]; then
  echo "  [10] owl std_gaussian_rvs: already patched."
else
  echo "  [10] owl: not vendored. Skipping."
fi

# Patch 11: batteries gates Gc.stat's live_stacks_words at ##V>=5.6##, but the
# field landed in OCaml 5.5; relax the gate.
BATGC_MLI="duniverse/batteries-included/src/batGc.mli"
if [ -f "$BATGC_MLI" ]; then
  if grep -q '##V>=5\.6## live_stacks_words' "$BATGC_MLI"; then
    sed_i -E '/live_stacks_words|Total space allocated outside of the OCaml heap|@since 5\.[56]\.0 \*\)/ s/##V>=5\.6##/##V>=5.5##/' "$BATGC_MLI"
    echo "  [11] batteries Gc.stat: relaxed live_stacks_words gate to ##V>=5.5##."
  elif ! grep -q 'live_stacks_words' "$BATGC_MLI"; then
    insert_after_offset "$BATGC_MLI" '##V>=4.12## forced_major_collections: int;' 3 \
      '##V>=5.5## live_stacks_words: int;' \
      '##V>=5.5## (** Total space allocated outside of the OCaml heap for stack fragments.' \
      '##V>=5.5##     @since 5.5.0 *)'
    echo "  [11] batteries Gc.stat: added live_stacks_words (##V>=5.5##)."
  else
    echo "  [11] batteries Gc.stat: already patched."
  fi
else
  echo "  [11] batteries: not vendored. Skipping."
fi

# Patch 12: mcl caml_mcl.c: add #include <stdint.h> for OCaml 5.6 trunk headers
MCL_CAML="vendor/pplacer/mcl/caml/caml_mcl.c"
if [ -f "$MCL_CAML" ] && ! grep -q 'stdint.h' "$MCL_CAML" 2>/dev/null; then
  # insert_at_line, not sed_i: `1a text` is GNU-only append syntax.
  insert_at_line "$MCL_CAML" 1 '#include <stdint.h>'
  echo "  [12] mcl caml_mcl.c: added #include <stdint.h>."
elif [ -f "$MCL_CAML" ]; then
  echo "  [12] mcl caml_mcl.c: already patched."
else
  echo "  [12] mcl: not vendored. Skipping."
fi

# Patch 13: pplacer tests.ml: PPLACER_TEST_LOOP repeats the suite N times in
# one process so olly observes the whole benchmark.
PPLACER_TESTS_ML="vendor/pplacer/tests/tests.ml"
if [ -f "$PPLACER_TESTS_ML" ] && ! grep -q 'PPLACER_TEST_LOOP' "$PPLACER_TESTS_ML" 2>/dev/null; then
  cat > "$PPLACER_TESTS_ML" << 'TESTS_ML_EOF'
open Ppatteries
open OUnit

let suite = "all tests" >::: [
  "guppy" >::: Test_all_guppy.suite;
  "pplacer" >::: Test_all_pplacer.suite;
  "rppr" >::: Test_all_rppr.suite;
  "json" >::: Test_json.suite;
]

(* PPLACER_TEST_LOOP env var (default 1): run the test suite N times in
   one process so olly observes the full benchmark.  Uses an env var
   (not Sys.argv) to avoid colliding with OUnit's own argv parsing
   (-only-test, -verbose, etc.).  See macro-benches README §"Iteration
   counts" for context.

   Correctness check only on the first iteration — at least one test
   (guppy:gaussian:coastal.v.upwelling) leaks state between runs and
   reports a false failure on repeats.  We exit non-zero if the first
   iteration fails; subsequent iterations are purely for wall-time
   scaling. *)
let _ =
  verbosity := 0;
  let loop = try int_of_string (Sys.getenv "PPLACER_TEST_LOOP") with _ -> 1 in
  if loop <= 1 then
    let _ = run_test_tt_main suite in ()
  else begin
    let results = run_test_tt suite in
    let any_fail = List.exists
      (function RFailure _ | RError _ -> true | _ -> false) results in
    if any_fail then exit 1;
    for _ = 2 to loop do
      let _ = run_test_tt suite in ()
    done
  end
TESTS_ML_EOF
  echo "  [13] pplacer tests.ml: added PPLACER_TEST_LOOP loop."
elif [ -f "$PPLACER_TESTS_ML" ]; then
  echo "  [13] pplacer tests.ml: already patched."
else
  echo "  [13] pplacer: not vendored. Skipping."
fi

# Patch 14: goblint.h declares __goblint_assume_join() with no args (void(void)
# under C23) but goblint.c defines it with a pthread_t; GCC 14+ rejects the
# mismatch. pthread_t is unsigned long on Linux/glibc, avoiding pthread.h.
GOBLINT_H="duniverse/analyzer/lib/goblint/runtime/include/goblint.h"
if [ -f "$GOBLINT_H" ] && grep -q '__goblint_assume_join(/\* pthread_t' "$GOBLINT_H" 2>/dev/null; then
  sed_i 's|void __goblint_assume_join(/\* pthread_t thread \*/);.*|void __goblint_assume_join(unsigned long thread); // pthread_t is unsigned long on Linux; avoids pthread.h vs kernel headers|' "$GOBLINT_H"
  echo "  [14] goblint.h: patched __goblint_assume_join signature (GCC 14+/C23)."
elif [ -f "$GOBLINT_H" ]; then
  echo "  [14] goblint.h: already patched."
else
  echo "  [14] goblint: not vendored. Skipping."
fi

# Patch 15: cpu's opam build runs autoconf/autoheader/configure to produce
# src/config.h; opam-monorepo does not, so do it here. configure probes for
# ocamlc, and $TOOLS_BIN only joins PATH at step [8], so set it explicitly.
# Failure is fatal: goblint would otherwise fail much later with
# `cpu_stubs.c:1:10: fatal error: config.h: No such file or directory`.
CPU_DIR="duniverse/cpu"
if [ -f "$CPU_DIR/configure.ac" ] && [ ! -f "$CPU_DIR/src/config.h" ]; then
  _cpu_log="$(mktemp)"
  if ( cd "$CPU_DIR" && PATH="$TOOLS_BIN:$PATH" \
         sh -c 'autoconf && autoheader && ./configure' ) >"$_cpu_log" 2>&1; then
    echo "  [15] cpu: generated src/config.h (autoconf/autoheader/configure)."
    rm -f "$_cpu_log"
  else
    echo "  [15] cpu: configure FAILED — goblint cannot build without src/config.h." >&2
    echo "  ---- last 20 lines of cpu configure output ----" >&2
    tail -20 "$_cpu_log" >&2
    rm -f "$_cpu_log"
    exit 1
  fi
elif [ -f "$CPU_DIR/src/config.h" ]; then
  echo "  [15] cpu: config.h already present."
else
  echo "  [15] cpu: not vendored. Skipping."
fi
echo ""

# Patch 16: the dune-universe json-data-encoding fork narrows Json_repr.Yojson
# to 8 constructors, but goblint treats it as Yojson.Safe.t; add `Tuple/`Variant
# and matching converter arms (unreachable for goblint configs).
JR_ML="duniverse/json-data-encoding/src/json_repr.ml"
if [ -f "$JR_ML" ] && ! grep -qF "Tuple of value list" "$JR_ML" 2>/dev/null; then
  python3 - <<'PY'
ml = "duniverse/json-data-encoding/src/json_repr.ml"; s = open(ml).read()
s = s.replace(
"""    | `Intlit of string
    | `List of value list
    | `Null
    | `String of string ]""",
"""    | `Intlit of string
    | `List of value list
    | `Null
    | `String of string
    | `Tuple of value list
    | `Variant of (string * value option) ]""", 1)
s = s.replace(
"""    | `Null -> `Null
    | `Bool b -> `Bool b

  let repr""",
"""    | `Null -> `Null
    | `Bool b -> `Bool b
    | `Tuple l -> `A l
    | `Variant (s, _) -> `String s

  let repr""", 1)
s = s.replace(
"""    | `Null -> `Null
    | `Bool b -> `Bool b
  in
  (* Rename `Assoc, `Int and `List *)""",
"""    | `Null -> `Null
    | `Bool b -> `Bool b
    | `Tuple _ | `Variant _ -> assert false  (* goblint configs never produce these *)
  in
  (* Rename `Assoc, `Int and `List *)""", 1)
open(ml, "w").write(s)
mli = "duniverse/json-data-encoding/src/json_repr.mli"; s = open(mli).read()
s = s.replace(
"""  | `List of yojson list  (** A JS array. *)
  | `Null  (** The [null] constant. *)
  | `String of string  (** An UTF-8 encoded string. *) ]""",
"""  | `List of yojson list  (** A JS array. *)
  | `Null  (** The [null] constant. *)
  | `String of string  (** An UTF-8 encoded string. *)
  | `Tuple of yojson list
  | `Variant of (string * yojson option) ]""", 1)
open(mli, "w").write(s)
PY
  echo "  [16] json-data-encoding: re-aligned Json_repr.Yojson with Yojson.Safe.t."
elif [ -f "$JR_ML" ]; then
  echo "  [16] json-data-encoding: already aligned."
else
  echo "  [16] json-data-encoding: not vendored. Skipping."
fi
echo ""

# Patch 17: catapult copies %{lib:bare_encoding:Bare_encoding.ml}, so
# bare_encoding must install its (capitalised) source.
BARE_DUNE="duniverse/bare-ocaml/src/dune"
if [ -f "$BARE_DUNE" ] && ! grep -qF "Bare_encoding.ml" "$BARE_DUNE" 2>/dev/null; then
  cat >> "$BARE_DUNE" <<'DUNE_EOF'

; Goblint's catapult dep copies Bare_encoding.ml/.mli via %{lib:bare_encoding:..}
; which needs the source installed under the lib dir (capitalised module name).
(install
 (section lib)
 (package bare_encoding)
 (files (bare_encoding.ml as Bare_encoding.ml) (bare_encoding.mli as Bare_encoding.mli)))
DUNE_EOF
  echo "  [17] bare_encoding: added source install stanza."
elif [ -f "$BARE_DUNE" ]; then
  echo "  [17] bare_encoding: already patched."
else
  echo "  [17] bare_encoding: not vendored. Skipping."
fi
echo ""

# Patch 18: OCaml >= 5.5 cannot infer the packaged-module signature at
# analyze_loop's two call sites; annotate them.
GOBLINT_CTRL="duniverse/analyzer/src/framework/control.ml"
# Guard on the unannotated call, not on the annotation appearing anywhere:
# upstream already annotates the definition.
if [ -f "$GOBLINT_CTRL" ] && grep -qF "analyze_loop (module CFG) file fs change_info" "$GOBLINT_CTRL" 2>/dev/null; then
  _n=$(grep -cF "analyze_loop (module CFG) file fs change_info" "$GOBLINT_CTRL")
  sed_i 's/analyze_loop (module CFG) file fs change_info/analyze_loop (module CFG : CfgBidirSkip) file fs change_info/g' "$GOBLINT_CTRL"
  echo "  [18] goblint control.ml: annotated ${_n} (module CFG : CfgBidirSkip) call site(s) (OCaml >= 5.5)."
  unset _n
elif [ -f "$GOBLINT_CTRL" ]; then
  echo "  [18] goblint control.ml: no unannotated call sites. Skipping."
else
  echo "  [18] goblint control.ml: not vendored. Skipping."
fi
echo ""

# Patch 24: -m32/-m64 are x86-only cpp flags; on aarch64 cpp rejects them and
# every goblint analysis dies in the preprocessor. Guard on the host being x86.
GOBLINT_MAIN="duniverse/analyzer/src/maingoblint.ml"
if [ -f "$GOBLINT_MAIN" ] && ! grep -q "host_is_x86" "$GOBLINT_MAIN" 2>/dev/null; then
  python3 - <<'PY'
p = "duniverse/analyzer/src/maingoblint.ml"
s = open(p).read()
old = """    let architecture_flag = match get_string "exp.architecture" with
      | "32bit" -> "-m32"
      | "64bit" -> "-m64"
      | _ -> assert false
    in
    cppflags := architecture_flag :: !cppflags"""
new = """    let architecture_flag = match get_string "exp.architecture" with
      | "32bit" -> "-m32"
      | "64bit" -> "-m64"
      | _ -> assert false
    in
    (* -m32/-m64 are x86-only cpp flags; on non-x86 hosts (e.g. aarch64) cpp
       rejects them and the word size is already native, so omit the flag. *)
    let host_is_x86 =
      try
        let ic = Unix.open_process_in "uname -m" in
        let m = try input_line ic with End_of_file -> "" in
        ignore (Unix.close_process_in ic);
        (match String.trim m with
         | "x86_64" | "amd64" | "i386" | "i486" | "i586" | "i686" -> true
         | _ -> false)
      with _ -> true  (* detection failed: keep old x86 behaviour *)
    in
    if host_is_x86 then
      cppflags := architecture_flag :: !cppflags"""
assert old in s, "maingoblint.ml architecture_flag block not found -- patch me"
open(p, "w").write(s.replace(old, new, 1))
print("  [24] goblint maingoblint.ml: guarded -m32/-m64 on x86 hosts only.")
PY
elif [ -f "$GOBLINT_MAIN" ]; then
  echo "  [24] goblint maingoblint.ml: already guarded. Skipping."
else
  echo "  [24] goblint maingoblint.ml: not vendored. Skipping."
fi
echo ""

# [21] sedlex fetches Unicode tables at build time with curl but without --fail,
# so an HTTP error body gets cached as a valid target and gen_unicode later dies
# with an assertion. -f also changes the rule digest, evicting a poisoned entry.
SEDLEX_DATA_DUNE="duniverse/sedlex/src/generator/data/dune"
if [ -f "$SEDLEX_DATA_DUNE" ]; then
  if grep -qE '^\s*-f$' "$SEDLEX_DATA_DUNE"; then
    echo "  [21] sedlex unicode download: already uses curl --fail. Skipping."
  else
    python3 - "$SEDLEX_DATA_DUNE" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
# `(run curl -L -s ...)` on one line, and the multi-line `(run\n curl\n -L\n -s\n ...)` form.
n1 = len(re.findall(r'\(run curl -L -s ', s))
s = s.replace('(run curl -L -s ', '(run curl -f -L -s ')
n2 = len(re.findall(r'^(\s*)curl\n\1-L\n\1-s\n', s, re.M))
s = re.sub(r'^(\s*)curl\n\1-L\n\1-s\n', r'\1curl\n\1-f\n\1-L\n\1-s\n', s, flags=re.M)
open(p, 'w').write(s)
print("  [21] sedlex unicode download: added --fail to {} inline + {} block curl rule(s).".format(n1, n2))
PYEOF
  fi
else
  echo "  [21] sedlex unicode download: not vendored. Skipping."
fi
echo ""

# Patch 25: extunix's gettid probe has no FreeBSD spelling
# (pthread_getthreadid_np in <pthread_np.h>), so devkit fails with
#   Error: Unbound value U.gettid
# Add a fifth alternative after the macOS one; Linux still matches SYS_gettid.
EXTUNIX_DISCOVER="duniverse/extunix/discover/discover.ml"
EXTUNIX_UNISTD="duniverse/extunix/src/unistd.c"
if [ -f "$EXTUNIX_DISCOVER" ] && [ -f "$EXTUNIX_UNISTD" ]; then
  if grep -q "EXTUNIX_USE_PTHREAD_GETTHREADID_NP" "$EXTUNIX_DISCOVER" 2>/dev/null; then
    echo "  [25] extunix gettid: already patched."
  else
    python3 - "$EXTUNIX_DISCOVER" "$EXTUNIX_UNISTD" <<'PYEOF'
import sys

disc, unistd = sys.argv[1], sys.argv[2]

s = open(disc).read()
old = '      [ DEFINE "EXTUNIX_USE_THREAD_SELFID"; I "sys/syscall.h"; S "syscall"; V "SYS_thread_selfid"];\n'
new = old + ('      [ DEFINE "EXTUNIX_USE_PTHREAD_GETTHREADID_NP"; I "pthread_np.h";'
             ' S "pthread_getthreadid_np" ];\n')
if old not in s:
    sys.exit("  [25] extunix gettid: discover.ml GETTID probe not in the expected shape")
open(disc, "w").write(s.replace(old, new, 1))

c = open(unistd).read()
old_c = """#elif defined(EXTUNIX_USE_THREAD_SELFID)
  pid_t tid = 0;
  tid = syscall(SYS_thread_selfid);
"""
new_c = old_c + """#elif defined(EXTUNIX_USE_PTHREAD_GETTHREADID_NP)
  int tid = pthread_getthreadid_np();
"""
if old_c not in c:
    sys.exit("  [25] extunix gettid: unistd.c gettid body not in the expected shape")
open(unistd, "w").write(c.replace(old_c, new_c, 1))
print("  [25] extunix gettid: added the FreeBSD pthread_getthreadid_np branch.")
PYEOF
  fi
else
  echo "  [25] extunix gettid: not vendored. Skipping."
fi
echo ""

# Patch 26: owl fails to link on FreeBSD (`undefined symbol: __kmpc_fork_call`):
# get_openmp_config has no freebsd arm, and FreeBSD's openblas .pc puts -fopenmp
# in cflags with no runtime in libs. Add -fopenmp/-lomp for freebsd, and -lomp
# whenever cflags ask for OpenMP with no runtime. The second diagnosis is
# inferred, not observed: if owl still fails, dump the assembled cflags/libs.
OWL_CONFIGURE="duniverse/owl/src/owl/config/configure.ml"
if [ -f "$OWL_CONFIGURE" ]; then
  if grep -q 'freebsd' "$OWL_CONFIGURE" 2>/dev/null; then
    echo "  [26] owl OpenMP: already patched."
  else
    python3 - "$OWL_CONFIGURE" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()

# (a) the missing match arm
old = '      | "macosx"    -> [ "-Xpreprocessor"; "-fopenmp" ], [ "-lomp" ]\n'
new = old + (
    '      (* FreeBSD cc is clang, but unlike macOS it needs no -Xpreprocessor. *)\n'
    '      | "freebsd"   -> [ "-fopenmp" ], [ "-lomp" ]\n'
)
if old not in s:
    sys.exit("  [26] owl OpenMP: get_openmp_config not in the expected shape")
s = s.replace(old, new, 1)

# (b) the runtime that pkg-config's -fopenmp never brings with it
old2 = (
    '      if not @@ C.c_test c test_linking ~c_flags:cflags ~link_flags:libs\n'
    '      then (\n'
    '        Printf.printf\n'
)
new2 = (
    '      (* FreeBSD: -fopenmp can arrive via pkg-config (openblas is built\n'
    '         with OpenMP there) while owl own OpenMP support is off, leaving\n'
    '         the __kmpc_* symbols undefined at link. Add the runtime when the\n'
    '         flags ask for OpenMP and nothing has supplied it. No-op\n'
    '         elsewhere. *)\n'
    '      let libs =\n'
    '        if get_os_type c = "freebsd"\n'
    '           && List.exists (fun f -> f = "-fopenmp") cflags\n'
    '           && not (List.exists (fun l -> l = "-lomp" || l = "-lgomp") libs)\n'
    '        then libs @ [ "-lomp" ]\n'
    '        else libs\n'
    '      in\n'
) + old2
if s.count(old2) != 1:
    sys.exit("  [26] owl OpenMP: the flag assembly is not in the expected shape")
s = s.replace(old2, new2, 1)

open(p, "w").write(s)
print("  [26] owl OpenMP: added the FreeBSD -fopenmp/-lomp handling.")
PYEOF
  fi
else
  echo "  [26] owl OpenMP: not vendored. Skipping."
fi
echo ""

# Patch 27: gsl-ocaml's discover.ml hardcodes /usr/include for the gsl headers;
# on FreeBSD gsl is under LOCALBASE, so pplacer dies with
#   Sys_error("/usr/include/gsl/gsl_cdf.h: No such file or directory")
# C_INCLUDE_PATH cannot help: OCaml opens the path itself. Probe the filesystem
# instead (/usr/include first, so Linux is unchanged). Why the default is reached
# at all is not established (pkg-config does emit -I/usr/local/include there).
GSL_DISCOVER="duniverse/gsl-ocaml/src/config/discover.ml"
if [ -f "$GSL_DISCOVER" ]; then
  if grep -q 'gsl_cdf.h' "$GSL_DISCOVER" 2>/dev/null; then
    echo "  [27] gsl-ocaml include search: already patched."
  else
    python3 - "$GSL_DISCOVER" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
old = '        let default_gsl_include = [ "/usr/include" ] in\n'
new = (
    '        (* Probe, do not assume. On FreeBSD gsl is under LOCALBASE, and\n'
    '           pkgconf strips -I/usr/local/include from --cflags because that\n'
    '           path is in its system include list, so the -I search below\n'
    '           finds nothing and this default is what is used. /usr/include\n'
    '           stays first, so Linux resolves exactly as before. *)\n'
    '        let default_gsl_include =\n'
    '          let candidates =\n'
    '            (match Sys.getenv_opt "LOCALBASE" with\n'
    '             | Some pfx -> [ Filename.concat pfx "include" ]\n'
    '             | None -> [])\n'
    '            @ [ "/usr/include"; "/usr/local/include"; "/opt/homebrew/include" ]\n'
    '          in\n'
    '          match\n'
    '            List.find_opt\n'
    '              (fun d -> Sys.file_exists (Filename.concat d "gsl/gsl_cdf.h"))\n'
    '              candidates\n'
    '          with\n'
    '          | Some d -> [ d ]\n'
    '          | None -> [ "/usr/include" ]\n'
    '        in\n'
)
if s.count(old) != 1:
    sys.exit("  [27] gsl-ocaml include search: not in the expected shape")
open(p, "w").write(s.replace(old, new, 1))
print("  [27] gsl-ocaml include search: now probes for gsl/gsl_cdf.h.")
PYEOF
  fi
else
  echo "  [27] gsl-ocaml include search: not vendored. Skipping."
fi
echo ""

# Patch 28: goblint's parallel/dune selects a domainslib implementation when the
# runtime switch happens to carry domainslib, dragging the switch's
# domain-local-await in beside the vendored one (`Error: Conflict between the
# following libraries`) and silently changing the threadpool being measured.
# Pin to the no-domainslib defaults, which every goblint figure was produced with.
GOBLINT_PARALLEL="duniverse/analyzer/src/util/parallel/dune"
if [ -f "$GOBLINT_PARALLEL" ]; then
  if ! grep -q 'domainslib ->' "$GOBLINT_PARALLEL" 2>/dev/null; then
    echo "  [28] goblint parallel select: already patched."
  else
    python3 - "$GOBLINT_PARALLEL" <<'PYEOF'
import re
import sys

p = sys.argv[1]
s = open(p).read()
# Drop every `(domainslib -> <file>)` alternative, leaving each select's
# default. Whitespace differs between the two blocks in this file, so match
# the line rather than an exact string.
new, n = re.subn(r'^[ \t]*\(domainslib -> [^\n]*\)\n', '', s, flags=re.M)
if n != 2:
    sys.exit("  [28] goblint parallel select: expected 2 domainslib "
             "alternatives, found %d" % n)
if 'no-domainslib' not in new:
    sys.exit("  [28] goblint parallel select: no-domainslib default missing")
open(p, "w").write(new)
print("  [28] goblint parallel select: pinned to the no-domainslib variants.")
PYEOF
  fi
else
  echo "  [28] goblint parallel select: not vendored. Skipping."
fi
echo ""

# Patch 29: CIL's real-GCC search tries `gcc` and hyphenated `gcc-N` only;
# FreeBSD's pkg installs gcc14 unhyphenated, so goblint dies with
#   Failure("couldn't find real gcc")
# (cc there is clang, which CIL rightly rejects). Unhyphenated names go after
# plain gcc, so Linux is unchanged.
CIL_GCC="duniverse/cil/bin/realGccConfigure.ml"
if [ -f "$CIL_GCC" ]; then
  if grep -q '"gcc14"' "$CIL_GCC" 2>/dev/null; then
    echo "  [29] cil real-gcc search: already patched."
  else
    python3 - "$CIL_GCC" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
old = 'let gccs = [\n  "gcc";\n'
new = (
    'let gccs = [\n'
    '  "gcc";\n'
    '  (* FreeBSD pkg installs versioned GCC unhyphenated: gcc14, not gcc-14.\n'
    '     After plain "gcc", so nothing changes where that exists. *)\n'
    '  "gcc16"; "gcc15"; "gcc14"; "gcc13"; "gcc12"; "gcc11";\n'
)
if s.count(old) != 1:
    sys.exit("  [29] cil real-gcc search: gccs list not in the expected shape")
open(p, "w").write(s.replace(old, new, 1))
print("  [29] cil real-gcc search: added the unhyphenated FreeBSD names.")
PYEOF
  fi
else
  echo "  [29] cil real-gcc search: not vendored. Skipping."
fi
echo ""

# Patch 30: same as 29 one layer up: goblint's preprocessor.ml falls back to
# `compgen -c cpp-`, which misses FreeBSD's cpp14, so the analysis aborts at
# run time with
#   Failure("No good preprocessor (cpp) found")
# Also search the unhyphenated prefix, hyphenated first. Needs a real GCC installed.
GOBLINT_CPP="duniverse/analyzer/src/util/preprocessor.ml"
if [ -f "$GOBLINT_CPP" ]; then
  if grep -q 'compgen "cpp"' "$GOBLINT_CPP" 2>/dev/null; then
    echo "  [30] goblint preprocessor search: already patched."
  else
    python3 - "$GOBLINT_CPP" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
old = '      compgen "cpp-" (* only run compgen if default was bad *)\n'
new = ('      (* FreeBSD names it cpp14, not cpp-14, so the hyphenated prefix\n'
       '         finds nothing there. Hyphenated first: Linux is unchanged. *)\n'
       '      (compgen "cpp-" @ compgen "cpp") (* only run compgen if default was bad *)\n')
if s.count(old) != 1:
    sys.exit("  [30] goblint preprocessor search: not in the expected shape")
open(p, "w").write(s.replace(old, new, 1))
print("  [30] goblint preprocessor search: added the unhyphenated cpp prefix.")
PYEOF
  fi
else
  echo "  [30] goblint preprocessor search: not vendored. Skipping."
fi
echo ""

# Patch 31: zarith's version rule pipes `grep "version" META | head -1` under
# dune's `bash -o pipefail`; META has two matching lines, so grep can take
# SIGPIPE and the rule fails with `Command exited with code 141` (a buffering
# race, frequent with FreeBSD's line-buffered grep). `grep -m1` needs no pipe.
ZARITH_DUNE="duniverse/Zarith/dune"
if [ -f "$ZARITH_DUNE" ]; then
  if grep -q 'grep -m1' "$ZARITH_DUNE" 2>/dev/null; then
    echo "  [31] zarith version rule: already patched."
  else
    python3 - "$ZARITH_DUNE" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
old = '(bash "grep \\"version\\" META | head -1")'
new = '(bash "grep -m1 \\"version\\" META")'
if s.count(old) != 1:
    sys.exit("  [31] zarith version rule: not in the expected shape")
open(p, "w").write(s.replace(old, new, 1))
print("  [31] zarith version rule: dropped the head -1 pipe (SIGPIPE under pipefail).")
PYEOF
  fi
else
  echo "  [31] zarith version rule: not vendored. Skipping."
fi
echo ""

# [22] sedlex's `(mode promote)` rule regenerates the shipped unicode.ml from
# tables downloaded from www.unicode.org on every clean build, which fails
# intermittently. Drop the rule; guarded on the shipped generated file being
# present. Patch [21] stays as a safety net.
SEDLEX_SYNTAX_DUNE="duniverse/sedlex/src/syntax/dune"
SEDLEX_UNICODE_ML="duniverse/sedlex/src/syntax/unicode.ml"
if [ ! -f "$SEDLEX_SYNTAX_DUNE" ]; then
  echo "  [22] sedlex unicode.ml rule: not vendored. Skipping."
elif ! grep -q "targets unicode.ml" "$SEDLEX_SYNTAX_DUNE"; then
  echo "  [22] sedlex unicode.ml rule: already removed. Skipping."
elif [ ! -f "$SEDLEX_UNICODE_ML" ] || ! grep -q "automatically generated" "$SEDLEX_UNICODE_ML"; then
  echo "  [22] sedlex unicode.ml rule: shipped unicode.ml missing/unrecognised — KEEPING the" >&2
  echo "       generation rule, which means this build needs www.unicode.org reachable." >&2
else
  python3 - "$SEDLEX_SYNTAX_DUNE" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """(rule
 (targets unicode.ml)
 (mode promote)
 (deps
  (:gen ../generator/gen_unicode.exe)
  (glob_files ../generator/data/*.txt))
 (action
  (run %{gen} %{targets})))
"""
new = """; unicode.ml generation rule removed by macro-benches setup-monorepo.sh [22]:
; the vendored tree ships the generated unicode.ml, and regenerating it required
; downloading the Unicode tables from www.unicode.org on every clean build.
"""
assert old in s, "unicode.ml rule not in the expected shape - patch [22] needs updating"
open(p, "w").write(s.replace(old, new, 1))
print("  [22] sedlex unicode.ml rule: removed; using the shipped unicode.ml.")
PYEOF
fi
echo ""

# [23] cpdf_squeeze merges N copies of one PDF, so every name/number tree key
# collides and camlpdf logs one flushed stderr line per duplicate (~13M per
# _large invocation, inside the measured region). Drop the log call only.
PDFTREE_ML="vendor/camlpdf/pdftree.ml"
if grep -q 'Pdfe.log "Warning Duplicate name/number tree key' "$PDFTREE_ML" 2>/dev/null; then
  sed_i '/Pdfe.log "Warning Duplicate name\/number tree key/d' "$PDFTREE_ML"
  echo "  [23] camlpdf duplicate-key warning: removed."
else
  echo "  [23] camlpdf duplicate-key warning: already patched (or file missing)."
fi
echo ""

echo "[8/9] Generating rocq config and dunestrap files..."
ROCQ_DIR="duniverse/rocq"

if [ -f "$ROCQ_DIR/config/coq_config.ml" ] && [ -f "$ROCQ_DIR/theories/Corelib/dune" ]; then
  echo "  Config and dunestrap files already exist. Skipping."
else
  export PATH="$TOOLS_BIN:$PATH"
  # `_build/install/default/lib` first: rocq's dunestrap rules run gen_rules.exe,
  # which resolves the rocq-runtime findlib package from $OCAMLPATH alone;
  # without it, on a switch without rocq installed:
  #   Fl_package_base.No_such_package("rocq-runtime", "")
  export OCAMLPATH="$MONOREPO_DIR/_build/install/default/lib:$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib:$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib/ocaml"

  echo "  Building rocq configure..."
  dune build "$ROCQ_DIR/config/coq_config.ml" --profile release

  # dune requires all fallback targets in the source tree, or none.
  for f in coq_config.ml coq_byte_config.ml coq_config.py dune.c_flags; do
    if [ -f "_build/default/$ROCQ_DIR/config/$f" ]; then
      cp "_build/default/$ROCQ_DIR/config/$f" "$ROCQ_DIR/config/$f"
    fi
  done
  echo "  Config files copied to source tree."

  echo "  Building dunestrap targets..."
  dune build "$ROCQ_DIR/corelib_dune" "$ROCQ_DIR/ltac2_dune" --profile release
  cp "_build/default/$ROCQ_DIR/corelib_dune" "$ROCQ_DIR/theories/Corelib/dune"
  cp "_build/default/$ROCQ_DIR/ltac2_dune" "$ROCQ_DIR/theories/Ltac2/dune"
  echo "  Dunestrap files installed."
fi

# Install rocq-runtime + rocq-core into a local prefix so coqc finds its stdlib
# (.vo files), plugins and META at runtime.
ROCQ_PREFIX="$MONOREPO_DIR/_rocq_prefix"
if [ -f "$ROCQ_PREFIX/rocq/lib/coq/theories/Init/Prelude.vo" ]; then
  echo "  Rocq already installed to _rocq_prefix/. Skipping."
else
  echo "  Installing rocq-runtime + rocq-core to _rocq_prefix/..."
  export PATH="$TOOLS_BIN:$PATH"
  # As above: coqc/coqdep resolve the in-workspace rocq-runtime through findlib,
  # which reads only $OCAMLPATH.
  export OCAMLPATH="$MONOREPO_DIR/_build/install/default/lib:$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib:$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib/ocaml"

  dune build duniverse/rocq/rocq-runtime.install --profile release
  DESTDIR="$ROCQ_PREFIX" dune install rocq-runtime --prefix /rocq --profile release

  # The generated theories dune files reference .vo deps via
  # %{workspace_root}/_build/../../install/default/lib/rocq-runtime/, i.e.
  # <parent_of_monorepo>/install/...; symlink that to the local install.
  ROCQ_INSTALL_LINK="$(dirname "$MONOREPO_DIR")/install/default/lib"
  mkdir -p "$ROCQ_INSTALL_LINK"
  ln -sfn "$ROCQ_PREFIX/rocq/lib/rocq-runtime" "$ROCQ_INSTALL_LINK/rocq-runtime"
  echo "  Symlink: $ROCQ_INSTALL_LINK/rocq-runtime -> _rocq_prefix"

  dune build duniverse/rocq/rocq-core.install --profile release
  DESTDIR="$ROCQ_PREFIX" dune install rocq-core --prefix /rocq --profile release

  echo "  Rocq installed to _rocq_prefix/."
fi
echo ""

# CI sets SKIP_TEST_BUILD=1: ci-build-all.sh runs straight after into
# _build-<tag>/, and this step targets the default _build/, so both would
# compile the duniverse twice.
if [ "${SKIP_TEST_BUILD:-0}" = "1" ]; then
  echo "[9/9] Test build SKIPPED (SKIP_TEST_BUILD=1)."
  echo ""
  echo "=== Setup complete! ==="
  exit 0
fi

# Smoke build of a hand-maintained subset (omits goblint and the other programs
# needing per-runtime prefixes); benchmarks/manifest.yml + ci-build-all.sh cover all.
echo "[9/9] Smoke build of a subset of benchmark binaries..."
export PATH="$TOOLS_BIN:$PATH"
export OCAMLPATH="$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib:$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib/ocaml"

dune build \
  duniverse/menhir/src/stage2/main.exe \
  vendor/cpdf-source/cpdfcommandrun.exe \
  duniverse/alt-ergo/src/bin/text/Main_text.exe \
  duniverse/rocq/topbin/coqc_bin.exe \
  benchmarks/ahrefs-devkit/htmlStream_bench.exe \
  duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/js_of_ocaml.exe \
  benchmarks/irmin/irmin_mem_rw.exe \
  duniverse/ocamlformat/bin/ocamlformat/main.exe \
  benchmarks/decompress/test_decompress.exe \
  benchmarks/eio/eio_bench.exe \
  benchmarks/sedlex/sedlex_bench.exe \
  vendor/pplacer/tests.exe \
  benchmarks/liquidsoap-lang/liq_bench.exe \
  benchmarks/frama-c/frama_c_eva.exe \
  --profile release

echo ""
echo "=== Setup complete! ==="
echo ""
echo "The smoke-build subset builds successfully."
echo "To build every program in benchmarks/manifest.yml: bash scripts/ci-build-all.sh"
echo ""
echo "To run benchmarks (standalone — no orchestrator needed):"
echo "  bash benchmarks/eio/eio.build.sh && ./benchmarks/eio/eio-runtime   # one bench"
echo "  bash scripts/ci-build-all.sh && bash scripts/ci-run-all.sh          # build all + smoke-run"
echo ""
echo "For cross-runtime / GC-parameter sweeps, plug in an orchestrator (running-ng"
echo "is one option) pointed here with: export RUNNING_MACRO_BENCH_DIR=$MONOREPO_DIR"
