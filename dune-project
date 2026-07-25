(lang dune 3.0)
(name macro-benches)
(generate_opam_files true)

; Package declarations for opam-monorepo dependency resolution.
;
; The x-opam-monorepo-opam-repositories field in .opam.template files
; points the solver at dune-universe overlays first, ensuring it picks
; dune-compatible versions of non-dune packages (zarith, fmt, etc.).
;
; cpdf/camlpdf don't use dune at all — vendored via scripts/vendor-cpdf.sh.

(package
 (name macro-bench-menhir)
 (allow_empty)
 (depends
  (menhir (>= 20231231))))

(package
 (name macro-bench-coq)
 (allow_empty)
 (depends
  (rocq-runtime (>= 9.0.0))))

(package
 (name macro-bench-alt-ergo)
 (allow_empty)
 (depends
  (alt-ergo (= 2.6.2))))

(package
 (name macro-bench-devkit)
 (allow_empty)
 (depends
  (devkit (>= 1.20240429))))

; cmdliner (2.x, for jsoo's Arg.Completion) and the dune_ lang level are both
; handled post-pull in setup-monorepo.sh ([2.3] / [3]) — opam-monorepo ignores
; version pins on these base/overlay packages anyway, and a `dune = 3.22.2` pin
; here actually makes the solve UNSAT (the set wants 3.23.1, which the [3] lang
; patch builds fine on the 3.22.1 binaries).  So jsoo stays unconstrained.
(package
 (name macro-bench-jsoo)
 (allow_empty)
 (depends
  (js_of_ocaml-compiler (= 6.2.0))))

(package
 (name macro-bench-irmin)
 (allow_empty)
 (depends
  (irmin (>= 3.10.0))))

(package
 (name macro-bench-ocamlformat)
 (allow_empty)
 (depends
  (ocamlformat (>= 0.27.0))))

(package
 (name macro-bench-decompress)
 (allow_empty)
 (depends
  (decompress (>= 1.5.0))
  (checkseum (>= 0.2.0))
  (bigstringaf (>= 0.2.0))
  (memtrace (>= 0.2.3))))

(package
 (name macro-bench-eio)
 (allow_empty)
 (depends
  (eio_main (>= 1.0))))

(package
 (name macro-bench-owl)
 (allow_empty)
 (depends
  (owl (>= 1.0))))

; liquidsoap-lang: pure OCaml language compiler (no audio/video C deps).
(package
 (name macro-bench-liquidsoap-lang)
 (allow_empty)
 (depends
  (liquidsoap-lang (>= 2.4.0))))

; pplacer is vendored manually (not in opam).  These are its OCaml deps.
(package
 (name macro-bench-pplacer)
 (allow_empty)
 (depends
  (batteries (>= 3.6.0))
  (gsl (>= 1.25.0))
  (sqlite3 (>= 5.0.0))
  (camlzip (>= 1.11))
  (csv (>= 2.4))
  (xmlm (>= 1.3.0))
  (ounit2 (>= 2.2.0))))

; frama-c is vendored manually (scripts/vendor-frama-c.sh — 32.1 is not
; in opam, and we build only a trimmed kernel+EVA, no WP/why3/GUI/apron).
; These are the OCaml deps of the kernel + EVA subtree only.  yaml is the
; one dep not already pulled by another benchmark.
(package
 (name macro-bench-frama-c)
 (allow_empty)
 (depends
  (zarith (>= 1.13))
  (ocamlgraph (>= 2.0.0))
  (menhir (>= 20181006))
  (yojson (>= 2.0.0))
  (yaml (>= 3.0.0))
  (camlzip (>= 1.11))
  (dune-site (>= 3.13.0))
  (ppx_deriving (>= 5.0))
  (ppx_deriving_yojson (>= 3.0))
  (ppx_deriving_yaml (>= 0.2.0))
  (ppx_inline_test (>= 0.17.0))))

; goblint: static analyser (ocaml#13733 regression reproducer).  Vendored
; via opam-monorepo (goblint + goblint-cil + deps are pure dune).  apron is
; REQUIRED by the svcomp config but is non-dune (configure/make + camlidl),
; so it is listed opam-provided (see the .opam.template) to keep the lock
; from trying to vendor it; it is supplied instead from a vendored,
; per-runtime prefix built by scripts/vendor-apron.sh (see
; benchmarks/goblint/goblint.build.sh).
(package
 (name macro-bench-goblint)
 (allow_empty)
 (depends
  (goblint (= 2.7.1))
  ; catapult's core lib copies Bare_encoding + runs bare-codegen at build time,
  ; but catapult's opam doesn't declare it (optional there); name it so the
  ; lock vendors it.
  (bare_encoding (>= 0.3.0))))

; infer: Meta's multi-language static analyzer, built java-only (clang /
; erlang / hack / python / rust / swift disabled).  Infer's own build is
; autoconf + make that *generates* its dune files, so it is not an
; opam-monorepo-buildable opam package; the source (with java-only dune
; files generated at vendor time) is vendored manually via
; scripts/vendor-infer.sh, and its OCaml deps are declared here.  The
; system libs (sqlite3, zlib, gmp) are opam-provided (see .opam.template).
; The core / ppx_* v0.17 band matches what the lock already pins (base
; v0.17.3, ppx_compare v0.17.0), so adding infer pushes only lower bounds.
; javalib + sawja are non-dune (native configure/Makefile) and are NOT
; declared anywhere in the lock (infer is manually vendored, so its deps are
; under our control; marking them opam-provided drags their opam dep cone
; into the global opam-provided solve and collides with devkit's libevent).
; They are built per-runtime into a prefix by scripts/vendor-javalib-sawja.sh
; and exposed to infer's dune build via OCAMLPATH (apron model).
(package
 (name macro-bench-infer)
 (allow_empty)
 (depends
  (ANSITerminal (>= 0.7))
  (atdgen (>= 2.15.0))
  (base64 (>= 3.0.0))
  bheap
  (cmdliner (>= 1.0.0))
  (core (and (>= v0.17.1) (< v0.18)))
  (fmt (>= 0.9.0))
  iter
  (memtrace (>= 0.1.2))
  (menhir (>= 20220210))
  (mtime (>= 2))
  ocamlgraph
  (parmap (>= 1.0-rc8))
  ppx_blob
  (ppx_compare (and (>= v0.17) (< v0.18)))
  (ppx_enumerate (and (>= v0.17) (< v0.18)))
  (ppx_expect (and (>= v0.17) (< v0.18)))
  (ppx_fields_conv (and (>= v0.17) (< v0.18)))
  (ppx_yojson_conv (and (>= v0.17) (< v0.18)))
  (sedlex (>= 3.0))
  (spawn (>= v0.17.0))
  sqlite3
  (tdigest (>= 2.0.0))
  (xmlm (>= 1.2.0))
  (yojson (>= 1.7.0))
  (zarith (>= 1.7))))
