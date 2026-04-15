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
