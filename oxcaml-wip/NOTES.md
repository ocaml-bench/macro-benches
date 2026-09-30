# OxCaml two-copies experiment (paused 2026-09-30)

Working notes, not a design doc. Paused in favour of dropping ppx
dependencies first (vendor ppx-expanded sources); resume after that lands.

## Status

On top of branch `oxcaml-portable` (setup-oxcaml.sh fixes [32]-[46]):

| Compiler | Result |
|---|---|
| OxCaml trunk be90cb46 (5.4.0-ox7 recipe) | 79/95 |
| OCaml 5.4.1 | 95/95 (verified before the base/ppx_bench variants and mapper.mll fix; re-verify) |

Still failing on OxCaml (all blocked on base v0.17 source vs OxCaml stdlib modes,
e.g. `base/src/buffer.ml:13`, `base/src/linked_queue0.ml:17`):
frama_c_eva_t, frama_c_eva_sqlite{,_small,_default,_large},
ocamlformat_rocq{,_small,_default,_large}, liq_parse_typecheck{,_small,_default,_large},
infer_{small,default,large}. Agreed next step there: portable patches to v0.17.

## Reproduce

After `make setup` (and vendor-infer for the infer patch):

    OXSRC=<oxcaml checkout at be90cb46> bash oxcaml-wip/reproduce.sh

`scripts/vendor-apron.sh` carries the apron fixes directly (applied after its reset).
Iterate with `L=<scratch> bash oxcaml-wip/tools/one.sh <program>...`.

## What differs between the OxCaml and OCaml builds

All OxCaml-specific code is build-time ppx code; no benchmark links ppxlib, and
`ppx_deriving.runtime` is byte-identical in both copies. Generated code is
expected to be identical but this is not verified.

- OxCaml copies (`duniverse/<pkg>/ox/`, every stanza gated on `%{ocaml_version}`):
  ppxlib, ppxlib_jane (from OxCaml `external/`), ppx_deriving
  (patricoferris/ppx_deriving@4cb09f5, = 6.1.1+ox). New OxCaml-only package: sexp_type@6d16004.
- Per-file variants (`X.upstream.ml` / `X.oxcaml.ml` + dune rule on
  `%{ocaml_version}`, same idiom as OxCaml's own ocaml-compiler-libs read_cma):
  sedlex ppx_sedlex (+ox patch), lwt ppx_lwt (+ox 6.0.0 patch adapted to 6.1.0),
  and hand-written (no OxCaml version exists): extunix ppx_have, ppx_deriving_yaml,
  repr ppx_repr, infer ppx_show, ppx_deriving_hash, ppx_deriving_yojson, goblint's
  vendored ppx_easy_deriving, ppx_bench, base import0.ml.
- Why rewriters need variants: OxCaml's ppxlib AST is not source-compatible with
  upstream (Ptyp_var/Ptyp_any carry jkinds, labelled tuples, Pcstr_tuple of
  constructor_argument, no Ptyp_open, no pvb_constraint, no pexp_function_cases).

## Portable fixes found here (to move into setup-oxcaml.sh)

- js_of_ocaml `compiler/lib/ocaml_compiler.ml`: inside `[@@if oxcaml]`,
  `Const_untagged_char` now carries an int.
- devkit `action.ml` (random_int), `httpev.ml` and `parallel.ml` (waitpid): eta-expansion.
- goblint `analyzer/src/util/std/gobRef.ml` `wrap`: eta-expansion (only caller applies fully).
- apron: OxCaml's public `caml/misc.h` includes `<stdbool.h>`, clashing with
  `ap_config.h`'s `typedef char bool` (fix keeps char bool on both); mlapronidl
  needs `-for-pack Apron` on `.cmi`/`.cmo` rules (same cause as [44]).
- base `shadow-stdlib/gen/mapper.mll`: kind-annotated types (`type t : k`) need
  the manifest after the kind; rule never fires on stock.

## Findings for upstream

- oxcaml/opam-repository (main f1bd228, also dev/unified): every `+ox` ppx package
  (ppxlib/ppxlib_ast 0.33.0+ox*, base/ppxlib_jane v0.18~preview, sedlex, lwt_ppx,
  ppx_deriving, js_of_ocaml) requires `ocaml < 5.3.0`; on 5.4.0-ox7 none resolve.
- OxCaml's Makefile has `jsoo-install-shipped` (ships ppxlib, ppxlib_jane, jsoo
  with the compiler) but the opam 5.4.0-ox7 recipe does not install them.
- Jane Street repos have `oxcaml` branches (all vendored ones except gel, result,
  spawn), dated 2026-07-10, older than OxCaml trunk.
- dune: `cinaps` and `documentation` stanzas reject `enabled_if`.
