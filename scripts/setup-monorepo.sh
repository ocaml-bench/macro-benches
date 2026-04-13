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
bash scripts/vendor-cpdf.sh
echo ""

# ---- Vendor zarith (+ rocq, but we remove vendor/rocq) ----
echo "[5/9] Vendoring zarith..."
bash scripts/vendor-coq.sh
# rocq is already in duniverse — remove vendor/rocq to avoid duplication
rm -rf vendor/rocq
echo "  Removed vendor/rocq (using duniverse/rocq instead)."
echo ""

# ---- Vendor devkit deps (libevent + ocurl) ----
echo "[6/9] Vendoring devkit deps (libevent + ocurl)..."
bash scripts/vendor-devkit-deps.sh
# If opam-monorepo also pulled ocurl into duniverse/, remove the vendor one
if [ -d duniverse/ocurl ] && [ -d vendor/ocurl ]; then
  rm -rf vendor/ocurl
  echo "  Removed vendor/ocurl (using duniverse/ocurl instead)."
fi
# Same for menhir (vendor/menhir is a leftover, duniverse/menhir is canonical)
if [ -d duniverse/menhir ] && [ -d vendor/menhir ]; then
  rm -rf vendor/menhir
  echo "  Removed vendor/menhir (using duniverse/menhir instead)."
fi
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
  sed -i '/(public_name alt-ergo)/d; /^  (package alt-ergo)$/d' "$ALT_ERGO_DUNE"
  echo "  [2] alt-ergo public_name: removed."
else
  echo "  [2] alt-ergo public_name: already removed."
fi

# Patch 3: dune_ version — already done in step 3
echo "  [3] dune_ version: done in step 3."

# Patch 4: ppxlib 5.6 support (replace with main branch)
if [ -f duniverse/ppxlib/ast/versions/ast_506.ml ]; then
  echo "  [4] ppxlib 5.6 support: already has Ast_506."
else
  echo "  [4] ppxlib 5.6 support: replacing with main branch..."
  rm -rf duniverse/ppxlib
  git clone --depth=1 https://github.com/ocaml-ppx/ppxlib.git duniverse/ppxlib
  rm -rf duniverse/ppxlib/.git
  echo "  [4] ppxlib replaced."
fi

# Patch 5: lwt 5.6 support (replace with latest)
if grep -q 'socketaddr' duniverse/lwt/src/unix/unix_c/unix_socketaddr.h 2>/dev/null; then
  echo "  [5] lwt 5.6 support: already up to date."
else
  echo "  [5] lwt 5.6 support: replacing with latest..."
  rm -rf duniverse/lwt
  git clone --depth=1 https://github.com/ocsigen/lwt.git duniverse/lwt
  rm -rf duniverse/lwt/.git
  echo "  [5] lwt replaced."
fi

# Patch 6: devkit lwt 6.x compat (engine_id extension)
DEVKIT_LWT="duniverse/devkit/lwt_engines.ml"
if grep -q 'Engine_id__libevent' "$DEVKIT_LWT" 2>/dev/null; then
  echo "  [6] devkit lwt 6.x compat: already patched."
else
  sed -i '/^(\*\* libevent-based engine for lwt \*\)$/a type Lwt_engine.engine_id += Engine_id__libevent' "$DEVKIT_LWT"
  sed -i '/inherit Lwt_engine.abstract$/a\  method id = Engine_id__libevent' "$DEVKIT_LWT"
  echo "  [6] devkit lwt 6.x compat: patched."
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
