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
