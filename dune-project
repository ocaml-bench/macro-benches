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

; cmdliner >= 2.0: jsoo's ocaml-5.6 branch uses Cmdliner.Arg.Completion
; (added in 2.0).  Without this lower bound the solver picks 1.3.0+dune,
; which lacks that API and breaks the jsoo build.  The dune-universe overlay
; provides 2.1.1+dune, which this constraint pins the lock to.
; dune = 3.22.2: the switch dune binaries are 3.22.1, and setup-monorepo's
; dune_ lang patch only matches "3.22"; letting the solver bump dune to 3.23
; leaves duniverse/dune_ at lang 3.23, which the 3.22.1 binaries can't parse.
; Pinning to 3.22.2 (the previously-locked version) keeps the build working.
(package
 (name macro-bench-jsoo)
 (allow_empty)
 (depends
  (js_of_ocaml-compiler (= 6.2.0))
  (cmdliner (>= 2.0.0))
  (dune (= 3.22.2))))

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
  (bigstringaf (>= 0.2.0))))

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
  (goblint (= 2.5.0))))
