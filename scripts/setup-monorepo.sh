#!/usr/bin/env bash
# setup-monorepo.sh — Full setup of the macro-benches monorepo.
#
# Populates duniverse/ and vendor/, applies all required patches, generates
# rocq's config + dunestrap files, and runs a test build of all benchmarks.
#
# Prerequisites:
#   - opam 2.3+ available (at /usr/local/bin/opam or on PATH)
#   - An opam switch with dune + ocamlfind (default: "running-ng-tools")
#   - System packages: libgmp-dev, libevent-dev, libcurl4-openssl-dev,
#                      libpcre3-dev, zlib1g-dev
#
# Usage:
#   bash scripts/setup-monorepo.sh
#
# After setup, run benchmarks via:
#   cd ~/running-ng
#   RUNNING_MACRO_BENCH_DIR=~/macro-benches \
#   CONFIG_FILE=src/running/config/macrobenchmarks_monorepo.yml \
#     bash run_ocaml_bench_gc_sweep.sh
set -euo pipefail

MONOREPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MONOREPO_DIR"

_OPAM=$([[ -x /usr/local/bin/opam ]] && echo /usr/local/bin/opam || command -v opam)
TOOLS_SWITCH="${TOOLS_SWITCH:-running-ng-tools}"
TOOLS_BIN="$("$_OPAM" var prefix --switch="$TOOLS_SWITCH" 2>/dev/null)/bin"

echo "=== Macro-benches monorepo setup ==="
echo "Monorepo dir: $MONOREPO_DIR"
echo "Tools switch: $TOOLS_SWITCH ($TOOLS_BIN)"
echo ""

# ---- Ensure tools switch has required packages ----
echo "[1/9] Ensuring tools switch has opam-monorepo + zarith..."
"$_OPAM" install --switch "$TOOLS_SWITCH" --yes opam-monorepo zarith dune ocamlfind
echo ""

# ---- Pull vendored sources ----
echo "[2/9] Pulling vendored sources (opam monorepo pull)..."
if [ -d duniverse ] && [ "$(ls duniverse/ | wc -l)" -gt 0 ]; then
  echo "  duniverse/ already populated ($(ls duniverse/ | wc -l) packages). Skipping."
  echo "  To re-pull, remove duniverse/ first."
else
  OPAMSWITCH="$TOOLS_SWITCH" "$_OPAM" monorepo pull --lockfile=macro-benches.opam.locked
fi
echo ""

# ---- Patch dune_ version (3.22 → 3.21) ----
echo "[3/9] Patching duniverse/dune_/dune-project (lang dune 3.22 → 3.21)..."
if grep -q 'lang dune 3.22' duniverse/dune_/dune-project 2>/dev/null; then
  sed -i 's/lang dune 3.22/lang dune 3.21/' duniverse/dune_/dune-project
  rm -rf duniverse/dune_/test
  echo "  Patched."
else
  echo "  Already patched (or version differs). Skipping."
fi
echo ""

# ---- Vendor cpdf + camlpdf ----
echo "[4/9] Vendoring cpdf + camlpdf..."
if [ -d vendor/camlpdf ] && [ -d vendor/cpdf-source ]; then
  echo "  vendor/camlpdf and vendor/cpdf-source already exist. Skipping."
else
  bash scripts/vendor-cpdf.sh
fi
echo ""

# ---- Vendor zarith ----
echo "[5/9] Vendoring zarith..."
if ls duniverse/[Zz]arith*/zarith.opam >/dev/null 2>&1; then
  echo "  zarith already in duniverse (dune-universe +dune version). Skipping manual vendor."
elif [ -d vendor/zarith ]; then
  echo "  vendor/zarith already exists. Skipping."
else
  bash scripts/vendor-coq.sh
  # rocq is already in duniverse — remove vendor/rocq to avoid duplication
  rm -rf vendor/rocq
  echo "  Removed vendor/rocq (using duniverse/rocq instead)."
fi
echo ""

# ---- Vendor devkit deps (libevent + ocurl) ----
echo "[6/9] Vendoring devkit deps (libevent + ocurl)..."
if [ -d vendor/libevent ]; then
  echo "  vendor/libevent already exists. Skipping."
else
  bash scripts/vendor-devkit-deps.sh
  # If opam-monorepo also pulled ocurl into duniverse/, remove the vendor one
  if [ -d duniverse/ocurl ] && [ -d vendor/ocurl ]; then
    rm -rf vendor/ocurl
    echo "  Removed vendor/ocurl (using duniverse/ocurl instead)."
  fi
fi
# Clean up any stale duplicates between vendor/ and duniverse/
for pkg in ocurl menhir; do
  if [ -d "duniverse/$pkg" ] && [ -d "vendor/$pkg" ]; then
    rm -rf "vendor/$pkg"
    echo "  Removed vendor/$pkg (using duniverse/$pkg instead)."
  fi
done
echo ""

# ---- Vendor pplacer + mcl ----
echo "[6b/9] Vendoring pplacer + mcl..."
bash scripts/vendor-pplacer.sh
echo ""

# ---- Apply vendored source patches ----
echo "[7/9] Applying vendored source patches..."

# Patch 1: alt-ergo ppx_blob paths (workspace-root-relative)
THEORIES_ML="duniverse/alt-ergo/src/lib/util/theories.ml"
if grep -q '\[%blob "src/preludes/' "$THEORIES_ML" 2>/dev/null; then
  sed -i 's|\[%blob "src/preludes/|\[%blob "duniverse/alt-ergo/src/preludes/|g' "$THEORIES_ML"
  echo "  [1] alt-ergo ppx_blob paths: patched."
else
  echo "  [1] alt-ergo ppx_blob paths: already patched."
fi

# Patch 2: alt-ergo public_name removal from Main_text executable
ALT_ERGO_DUNE="duniverse/alt-ergo/src/bin/text/dune"
if grep -q '(public_name alt-ergo)' "$ALT_ERGO_DUNE" 2>/dev/null; then
  # Rewrite the file entirely — sed is too fragile for nested s-expressions
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

# Patch 3: dune_ version — already done in step 3
echo "  [3] dune_ version: done in step 3."

# Patch 4: ppxlib 5.6 support (replace with main branch)
if [ -f duniverse/ppxlib/astlib/ast_506.ml ]; then
  echo "  [4] ppxlib 5.6 support: already has Ast_506."
else
  echo "  [4] ppxlib 5.6 support: replacing with main branch..."
  rm -rf duniverse/ppxlib
  git clone --depth=1 https://github.com/ocaml-ppx/ppxlib.git duniverse/ppxlib
  rm -rf duniverse/ppxlib/.git
  echo "  [4] ppxlib replaced."
fi

# Patch 5: lwt 5.6 support (replace with latest)
if grep -q 'caml_unix_get_sockaddr' duniverse/lwt/src/unix/unix_c/unix_recv_send_utils.h 2>/dev/null; then
  echo "  [5] lwt 5.6 support: already has socketaddr fix."
else
  echo "  [5] lwt 5.6 support: replacing with latest..."
  rm -rf duniverse/lwt
  git clone --depth=1 https://github.com/ocsigen/lwt.git duniverse/lwt
  rm -rf duniverse/lwt/.git
  echo "  [5] lwt replaced."
fi

# Patch 6: devkit lwt 6.x compat (engine_id extension)
# Only needed if lwt >= 6.1.1 (which adds virtual method `id` to Lwt_engine.abstract).
# With the locked lwt 6.1.0, this patch is NOT needed.
DEVKIT_LWT="duniverse/devkit/lwt_engines.ml"
if grep -q 'method virtual id' duniverse/lwt/src/unix/lwt_engine.mli 2>/dev/null; then
  if grep -q 'Engine_id__libevent' "$DEVKIT_LWT" 2>/dev/null; then
    echo "  [6] devkit lwt 6.x compat: already patched."
  else
    sed -i '/libevent-based engine for lwt/a type Lwt_engine.engine_id += Engine_id__libevent' "$DEVKIT_LWT"
    sed -i '/inherit Lwt_engine.abstract/a\  method id = Engine_id__libevent' "$DEVKIT_LWT"
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
  sed -i 's/^let set base event fd etype persist/let set base event fd etype ~persist/' "$LIBEVENT_ML"
  sed -i 's/^let set_timer base event persist/let set_timer base event ~persist/' "$LIBEVENT_ML"
  sed -i 's/^let set_signal base event signal persist/let set_signal base event ~signal ~persist/' "$LIBEVENT_ML"
  echo "  [7] libevent labels: patched."
fi

# Patch 8: js_of_ocaml public_name removal from executable stanza
# Only remove from the (executable ...) block, not from (install ...) stanzas.
JSOO_DUNE="duniverse/js_of_ocaml/compiler/bin-js_of_ocaml/dune"
if [ -f "$JSOO_DUNE" ] && grep -q '(public_name js_of_ocaml)' "$JSOO_DUNE" 2>/dev/null; then
  # Remove only the public_name line (the package line in the executable
  # stanza is on the same line pattern but also appears in install stanzas,
  # so we use a targeted approach: remove the 2nd and 3rd lines of the file)
  sed -i '2{/(public_name js_of_ocaml)/d}' "$JSOO_DUNE"
  sed -i '2{/(package js_of_ocaml-compiler)/d}' "$JSOO_DUNE"
  echo "  [8] jsoo public_name: removed from executable stanza."
elif [ -f "$JSOO_DUNE" ]; then
  echo "  [8] jsoo public_name: already removed."
else
  echo "  [8] jsoo: not vendored. Skipping."
fi

# Patch 9: ocamlformat public_name removal (only from executable stanza)
OCFMT_DUNE="duniverse/ocamlformat/bin/ocamlformat/dune"
if [ -f "$OCFMT_DUNE" ] && grep -q '(public_name ocamlformat)' "$OCFMT_DUNE" 2>/dev/null; then
  # Remove only the first occurrence of public_name and the package line
  # immediately after it (lines 14-15 in the executable stanza).
  sed -i '0,/(public_name ocamlformat)/{/(public_name ocamlformat)/d}' "$OCFMT_DUNE"
  sed -i '0,/^ (package ocamlformat)$/{/^ (package ocamlformat)$/d}' "$OCFMT_DUNE"
  echo "  [9] ocamlformat public_name: removed."
elif [ -f "$OCFMT_DUNE" ]; then
  echo "  [9] ocamlformat public_name: already removed."
else
  echo "  [9] ocamlformat: not vendored. Skipping."
fi

# Patch 10: owl C bug — std_gaussian_rvs called with arguments but takes none
OWL_EXPONPOW="duniverse/owl/src/owl/stats/owl_stats_dist_exponpow.c"
if [ -f "$OWL_EXPONPOW" ] && grep -q 'std_gaussian_rvs (a' "$OWL_EXPONPOW" 2>/dev/null; then
  sed -i 's/std_gaussian_rvs (a \/ sqrt (2.0))/gaussian_rvs (0, a \/ sqrt (2.0))/' "$OWL_EXPONPOW"
  sed -i 's/std_gaussian_rvs (B)/gaussian_rvs (0, B)/' "$OWL_EXPONPOW"
  echo "  [10] owl std_gaussian_rvs: patched (upstream C bug)."
elif [ -f "$OWL_EXPONPOW" ]; then
  echo "  [10] owl std_gaussian_rvs: already patched."
else
  echo "  [10] owl: not vendored. Skipping."
fi

# Patch 11: batteries Gc.stat — add live_stacks_words for OCaml 5.6 trunk
BATGC_MLI="duniverse/batteries-included/src/batGc.mli"
if [ -f "$BATGC_MLI" ] && ! grep -q 'live_stacks_words' "$BATGC_MLI" 2>/dev/null; then
  sed -i '/##V>=4.12## forced_major_collections: int;/{
    N;N;N
    a##V>=5.6## live_stacks_words: int;\n##V>=5.6## (** Total space allocated outside of the OCaml heap for stack fragments.\n##V>=5.6##     @since 5.6.0 *)
  }' "$BATGC_MLI"
  echo "  [11] batteries Gc.stat: added live_stacks_words for OCaml 5.6."
elif [ -f "$BATGC_MLI" ]; then
  echo "  [11] batteries Gc.stat: already patched."
else
  echo "  [11] batteries: not vendored. Skipping."
fi

# Patch 12: mcl caml_mcl.c — add #include <stdint.h> for OCaml 5.6 trunk headers
MCL_CAML="vendor/pplacer/mcl/caml/caml_mcl.c"
if [ -f "$MCL_CAML" ] && ! grep -q 'stdint.h' "$MCL_CAML" 2>/dev/null; then
  sed -i '1a #include <stdint.h>' "$MCL_CAML"
  echo "  [12] mcl caml_mcl.c: added #include <stdint.h>."
elif [ -f "$MCL_CAML" ]; then
  echo "  [12] mcl caml_mcl.c: already patched."
else
  echo "  [12] mcl: not vendored. Skipping."
fi
echo ""

# ---- Generate rocq config + dunestrap ----
echo "[8/9] Generating rocq config and dunestrap files..."
ROCQ_DIR="duniverse/rocq"

if [ -f "$ROCQ_DIR/config/coq_config.ml" ] && [ -f "$ROCQ_DIR/theories/Corelib/dune" ]; then
  echo "  Config and dunestrap files already exist. Skipping."
else
  export PATH="$TOOLS_BIN:$PATH"
  export OCAMLPATH="$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib:$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib/ocaml"

  # Generate coq_config.ml via dune fallback rule
  echo "  Building rocq configure..."
  dune build "$ROCQ_DIR/config/coq_config.ml" --profile release

  # Copy all fallback targets to source tree (dune requires all-or-nothing)
  for f in coq_config.ml coq_byte_config.ml coq_config.py dune.c_flags; do
    if [ -f "_build/default/$ROCQ_DIR/config/$f" ]; then
      cp "_build/default/$ROCQ_DIR/config/$f" "$ROCQ_DIR/config/$f"
    fi
  done
  echo "  Config files copied to source tree."

  # Generate dunestrap files (theories/Corelib/dune and theories/Ltac2/dune)
  echo "  Building dunestrap targets..."
  dune build "$ROCQ_DIR/corelib_dune" "$ROCQ_DIR/ltac2_dune" --profile release
  cp "_build/default/$ROCQ_DIR/corelib_dune" "$ROCQ_DIR/theories/Corelib/dune"
  cp "_build/default/$ROCQ_DIR/ltac2_dune" "$ROCQ_DIR/theories/Ltac2/dune"
  echo "  Dunestrap files installed."
fi

# Install rocq-runtime + rocq-core into a local prefix so coqc can
# find its stdlib (.vo files), plugins, and META at runtime.
ROCQ_PREFIX="$MONOREPO_DIR/_rocq_prefix"
if [ -f "$ROCQ_PREFIX/rocq/lib/coq/theories/Init/Prelude.vo" ]; then
  echo "  Rocq already installed to _rocq_prefix/. Skipping."
else
  echo "  Installing rocq-runtime + rocq-core to _rocq_prefix/..."
  export PATH="$TOOLS_BIN:$PATH"
  export OCAMLPATH="$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib:$("$_OPAM" var prefix --switch="$TOOLS_SWITCH")/lib/ocaml"

  # Build and install rocq-runtime
  dune build duniverse/rocq/rocq-runtime.install --profile release
  DESTDIR="$ROCQ_PREFIX" dune install rocq-runtime --prefix /rocq --profile release

  # The generated theories/Corelib/dune files reference .vo compilation deps
  # via %{workspace_root}/_build/../../install/default/lib/rocq-runtime/.
  # This resolves to <parent_of_monorepo>/install/default/lib/rocq-runtime/.
  # We create a symlink there pointing at our local install.
  ROCQ_INSTALL_LINK="$(dirname "$MONOREPO_DIR")/install/default/lib"
  mkdir -p "$ROCQ_INSTALL_LINK"
  ln -sfn "$ROCQ_PREFIX/rocq/lib/rocq-runtime" "$ROCQ_INSTALL_LINK/rocq-runtime"
  echo "  Symlink: $ROCQ_INSTALL_LINK/rocq-runtime -> _rocq_prefix"

  # Build and install rocq-core (theories / .vo files)
  dune build duniverse/rocq/rocq-core.install --profile release
  DESTDIR="$ROCQ_PREFIX" dune install rocq-core --prefix /rocq --profile release

  echo "  Rocq installed to _rocq_prefix/."
fi
echo ""

# ---- Test build ----
echo "[9/9] Test build of all benchmark binaries..."
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
  --profile release

echo ""
echo "=== Setup complete! ==="
echo ""
echo "All benchmark binaries build successfully."
echo ""
echo "To run benchmarks:"
echo "  cd ~/running-ng"
echo "  RUNNING_MACRO_BENCH_DIR=$MONOREPO_DIR \\"
echo "  CONFIG_FILE=src/running/config/macrobenchmarks_monorepo.yml \\"
echo "    bash run_ocaml_bench_gc_sweep.sh"
