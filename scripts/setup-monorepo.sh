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

# Patch 4: ppxlib 5.6 support
# BLOCKED: replacing ppxlib with git main breaks extunix and other packages
# that depend on ppxlib 0.38.0 APIs (pexp_function signature changed).
# Trunk (OCaml 5.6) support requires ppxlib to release a 5.6-compatible
# version AND all transitive deps to be updated. Until then, benchmarks
# that use ppxlib (alt-ergo, devkit, jsoo) only run on OCaml 5.4.x.
# Menhir, cpdf, and coq work on trunk since they don't use ppxlib.
echo "  [4] ppxlib 5.6 support: BLOCKED (see setup-monorepo.sh comments). Using locked 0.38.0."

# Patch 5: lwt 5.6 support
# Same blocker — lwt 6.1.0 has C stubs incompatible with OCaml 5.6's
# socketaddr.h, but upgrading lwt requires upgrading ppxlib too.
echo "  [5] lwt 5.6 support: BLOCKED (depends on ppxlib upgrade). Using locked 6.1.0."

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

# Patch 9: ocamlformat public_name removal
OCFMT_DUNE="duniverse/ocamlformat/bin/ocamlformat/dune"
if [ -f "$OCFMT_DUNE" ] && grep -q '(public_name ocamlformat)' "$OCFMT_DUNE" 2>/dev/null; then
  sed -i '/(public_name ocamlformat)/d' "$OCFMT_DUNE"
  sed -i '/(package ocamlformat)/d' "$OCFMT_DUNE"
  echo "  [9] ocamlformat public_name: removed."
elif [ -f "$OCFMT_DUNE" ]; then
  echo "  [9] ocamlformat public_name: already removed."
else
  echo "  [9] ocamlformat: not vendored. Skipping."
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
