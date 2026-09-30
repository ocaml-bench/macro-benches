# Portable (both compilers) changes, iteration log
1. duniverse/yojson/lib/write.ml: eta-expand write_{int,float,string}lit (= oxcaml yojson.2.2.2+ox patch)
2. duniverse/ocaml-extlib/src/extList.ml: eta-expand mem, memq; extString.ml: blit, index_from(_opt), rindex_from(_opt) (= oxcaml extlib.1.8.0+ox patch minus extArray.mli cppo gate)
3. vendor/camlpdf/pdfutil.ml: let mem = List.mem -> eta
4. duniverse/rocq/clib/int.ml: List.mem = List.memq -> eta
5. duniverse/lwt/src/unix/lwt_unix.cppo.ml: eta-expand do_{recv,send,recvfrom,sendto} (= unix part of oxcaml lwt.6.0.0+ox patch)
6. duniverse/eio/lib_eio/core/cells.ml: eta-expand Atomic.fetch_and_add branch
7. duniverse/repr/src/repr/type_random.ml: stage R.bool -> eta; type_binary.ml: stage Bytes.to_string -> eta
8. vendor/camlpdf/pdfops.ml: iter (Buffer.add_string b) -> eta
9. duniverse/devkit/ocamlnet_lite/netstring_tstring.ml: string_ops record fields sub/substring/blit_to_bytes/index_from/rindex_from -> eta
10. duniverse/repr/src/repr/type_binary.ml: to_bin `seq (Buffer.add_string buf)` -> eta (source of the local mode; line 369 left unchanged)
11. duniverse/batteries-included: batBytes blit, batQueue iter, batUTF8 Buf.add_string re-defined eta after include
12. vendor/.infer-js-src/extlib (infer's own extlib 1.8.0 copy): same eta-expansions as #2
13. batteries: batList mem/memq, batString Bytes.blit + include String index_from_opt/rindex_from_opt, batBytes blit_string, batQueue fold/transfer, batBuffer add_bytes/add_string/blit -> eta
14. devkit netstring_tstring bytes_ops blit_to_bytes = Bytes.blit -> eta
15. vendor/cpdf-source/cpdfyojson.ml (cpdf's bundled yojson, 4 copies): write_{int,float,string}lit -> eta
16. infer's extlib (vendor/.infer-js-src/extlib) is reset by vendor-javalib-sawja.sh `git checkout .` every build: patch must be applied inside that script after the reset
17. batteries batString: include String blit -> eta
18. javalib + sawja Makefiles (infer): add $(FOR_PACK) to .ml.cmo and .mli.cmi rules. OxCaml records the pack prefix in the .cmi (repro: scratchpad/forpack, a.mli w/o -for-pack + a.ml/b.ml with -> "a.cmx contains the description for unit A when P.A was expected"; stock 5.4.1 accepts). Applied in vendor-javalib-sawja.sh after reset. UPSTREAM candidate.
19. duniverse/iter/src/Iter.ml:890 `iter (Buffer.add_string b) seq` -> eta. A later partial application of a local-taking stdlib fn constrains iter's own (non-generalized) parameter mode, so `let iter f seq = seq f` stops matching its .mli (repro: scratchpad/iterrepro).
20. batteries batString: include String index_from, rindex_from -> eta
21. batteries batGc: define eventlog_pause/eventlog_resume as no-ops after include Gc. OxCaml removed these deprecated Gc functions (category F); stock 5.x implements both as `()` no-ops, so identical behaviour.
22. batteries batUnix: include Unix handle_unix_error -> eta (takes a `local once` function)
23. batteries batUnix: 38 Unix re-exports with local args (generated from OxCaml unix.mli) -> eta, incl. ?cloexec optional args
24. batteries batUnix: link, symlink, read_bigarray, write_bigarray, single_write_bigarray -> eta (cppo-gated ##V>=..## decls the first scan missed)
25. batteries batUnix: module LargeFile wrapper re-defining lseek, truncate -> eta
26. batteries batRandom State: 10 Random.State fns (int, full_int, *_in_range, int32/64, nativeint, float) -> eta; batBigarray Array0.set -> eta (cppo ##V>=4.5## prefix)
27. batteries batFile: let chmod = Unix.chmod -> eta (set_permissions = chmod)

## Blocker investigation (2026-09-30, throwaway tree ~/oxtest/macro-benches, not committed)
- ocaml_intrinsics_kernel v0.17.2: NOT inherently OxCaml-only. 8 of 26 [@@builtin] externals name intrinsics OxCaml be90cb46 no longer has (int32/int64/nativeint clz/ctz *_nonzero_unboxed_to_untagged, caml_sse2_float64_min/max). Stock ignores [@@builtin]; C stubs exist. Portable fix: drop [@@builtin] on those 8 in .ml AND .mli. Alternative: OxCaml flag -disable-builtin-check (falls back to C stub) but stock ocamlopt rejects the flag. VERIFIED: builds on OxCaml, stock 95/95.
- ctypes 0.24.0: NOT OxCaml-only. bigarray_kind's GADT match returns Genarray/Array1/2/3.kind unapplied; OxCaml's take `@ immutable`. Eta-expanding the 4 branches is portable (the +ox patch used OxCaml-only syntax instead). VERIFIED. TODO: minimal repro (plain `let f : ... = Genarray.kind` does NOT reproduce; needs the GADT/locally-abstract context).
- ocaml-compiler-libs read_cma: compiler-internals (Cmo_format.compunit vs Compilation_unit.t). In-repo per-compiler source via dune `(select compunit_name.ml from (stdlib_stable -> .oxcaml.ml) (-> .stock.ml))` WORKS (OxCaml ships findlib libs stdlib_stable/stdlib_upstream_compatible/stdlib_alpha/stdlib_beta and compiler-libs.frontend). Unblocks to ppxlib.
- NEW packaging difference: OxCaml splits compiler-libs; typing modules (Printtyp, Cmi_format, Subst) are in compiler-libs.frontend, not compiler-libs.common. Stock code linking compiler-libs.common for typing modules fails to LINK on OxCaml. Selecting on compiler-libs.frontend both picks the file and adds the dep on OxCaml only.
- base v0.17.3 shadow-stdlib gen: after select (cmi_sig) + frontend it runs, but its mapper.mll parses Printtyp OUTPUT; OxCaml prints kinds/modalities (`type nonrec in_channel = Stdlib.in_channel : value mod portable contended`, `@@ portable`) -> generated shadow_stdlib.mli syntax error. Genuinely compiler-specific (base v0.18 preview handles it).
- ppxlib astlib: OxCaml Parsetree differs (Parsetree.signature is a record with modalities, not a list; plus modes/kinds/etc). Every ppx goes through it -> genuinely needs OxCaml AST support (ppxlib +ox) and OxCaml-aware ppx rewriters.
- With E1+E2+E3: OxCaml 50/95 (from 45); stock 5.5.0 95/95.
