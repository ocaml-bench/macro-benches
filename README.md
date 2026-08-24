# macro-benches

A suite of real-world OCaml programs used as macro-benchmarks, for comparing
one OCaml runtime against another on workloads that look like the things people
actually run: compilers, provers, static analysers, a video pipeline, a
key-value store, and so on.

Every dependency is vendored into the repo with
[opam-monorepo](https://github.com/tarides/opam-monorepo), so every runtime
compiles byte-identical source. The only thing that changes between runs is the
compiler, which is the whole point: if a number moves, it is the runtime that
moved it, not a different version of some library that happened to get pulled
in.

You can use it two ways:

- **Standalone.** Run `make setup` once, then build any single benchmark under
  any opam switch and run the binary yourself.
- **Orchestrated.** Point an orchestrator such as
  [running-ng](https://github.com/udesou/running-ng) at the repo and let it
  manage per-runtime switches and drive cross-runtime, frame-pointer, flambda,
  or GC-parameter sweeps.

## The benchmarks

23 tools (21 active; `merlin` and `lavyek` disabled — see below). Each active
tool has an **input-size ladder**:`small` / `default` / `large` (a couple also
`huge`) rungs whose input is chosen so each reaches a different GC/runtime
regime, not just a bigger copy of the one below. A bare run
executes the `default` rung of every tool; other sizes are opt-in via a tag (see
[Run sweeps](#run-sweeps)). Older single-point benchmarks containing original anchors,
extra per-tool workloads, and the frozen issue reproducers are kept as
**legacy** benches, run only with `RUNNING_TAG=legacy`.

The table below sketches what each tool does (its `default` rung); each has a
page under [docs/benchmarks/](docs/benchmarks) with the full ladder and legacy
benches.

| Benchmark | `default` program | What it runs | Category |
|-----------|-------------------|--------------|----------|
| [menhir](docs/benchmarks/menhir.md) | `menhir_ocamly` | Builds the canonical LR(1) automaton for the OCaml grammar (`--canonical --list-errors`) | Text processing |
| [cpdf](docs/benchmarks/cpdf.md) | `cpdf_squeeze_default` | Merges 24 copies of an ~8.7 MB reference PDF and recompresses every object stream | Text/media |
| [alt-ergo](docs/benchmarks/alt-ergo.md) | `alt_ergo_chain_default` | Proves a 7000-step arithmetic congruence chain (native `.why`) | SMT solver |
| [coq](docs/benchmarks/coq.md) | `coqc_tree_default` | Coq kernel reduction of `tree_size (make_tree 18)` over unary `nat` | Proof assistant |
| [ahrefs-devkit](docs/benchmarks/ahrefs-devkit.md) | `devkit_htmlstream_default` | Devkit's `HtmlStream.parse` GC-stress suite at content scale 3 | Web |
| [irmin](docs/benchmarks/irmin.md) | `irmin_mem_rw_default` | 10000 keys written into one flat directory node of an in-memory Irmin store | Database |
| [ocamlformat](docs/benchmarks/ocamlformat.md) | `ocamlformat_rocq_default` | Formats a ~100k-line OCaml source (30x the reference workload) | Build tool |
| [decompress](docs/benchmarks/decompress.md) | `test_decompress_default` | Pure-OCaml zlib round-trip over a 256 MB payload | Compression |
| [eio](docs/benchmarks/eio.md) | `eio_conc_default` | 9000 producer/consumer fiber pairs, each on its own bounded stream (needs OCaml 5.2+) | Concurrency |
| [sedlex](docs/benchmarks/sedlex.md) | `sedlex_tokenize_default` | Tokenizes 6M generated lines, retaining every token | Text processing |
| [yojson](docs/benchmarks/yojson.md) | `ydump_repeat_default` | Parses a generated 771 MB JSON document (6M records) into a tree | Text processing |
| [zarith](docs/benchmarks/zarith.md) | `zarith_pi_default` | Computes 38000 digits of pi with GMP | ML/Numerics |
| [owl](docs/benchmarks/owl.md) | `owl_gc_default` | Gromov-Wasserstein distances over 500x500 matrices via OpenBLAS | ML/Numerics |
| [pplacer](docs/benchmarks/pplacer.md) | `pplacer_like_default` | Felsenstein pruning over a 55k-site alignment (GSL off-heap `Bigarray`s) | Bioinformatics |
| [ocamlc-compile-uucp](docs/benchmarks/ocamlc-compile-uucp.md) | `ocamlc_compile_uucp_default` | The runtime's own `ocamlc` compiling 8 replicas of the uucp Unicode library | Compiler |
| [liquidsoap-lang](docs/benchmarks/liquidsoap-lang.md) | `liq_parse_typecheck_default` | Parses and typechecks a generated ~1.8 MB Liquidsoap script | Compiler |
| [liq-video-frames](docs/benchmarks/liq-video-frames.md) | `liq_video_frames_pool_default` | A refcounted pool of 15000 4K YUV420 video frames (reproduces [#14533](https://github.com/ocaml/ocaml/issues/14533)) | Text/media |
| [frama-c](docs/benchmarks/frama-c.md) | `frama_c_eva_sqlite_default` | Frama-C EVA value analysis of the SQLite amalgamation at `-eva-precision 2` (reproduces [#11733](https://github.com/ocaml/ocaml/issues/11733)) | Static analysis |
| [goblint](docs/benchmarks/goblint.md) | `goblint_gen_default` | Goblint octagon (apron) analysis of a 165-variable bit-vector state machine (reproduces [#13733](https://github.com/ocaml/ocaml/issues/13733)) | Static analysis |
| [js_of_ocaml](docs/benchmarks/js_of_ocaml.md) | `jsoo_default` | Compiles a 14 MB bytecode (80 replicas of the JSOO classics) to JavaScript | Compiler |
| [infer](docs/benchmarks/infer.md) | Infer's multicore Java analysis (Pulse) over a fixed slice of a real bytecode corpus (guava, byte-buddy, lucene, bcprov) | 

Two more tools ship in the tree but are currently disabled:
[merlin](docs/benchmarks/merlin.md) (an upstream race in the domains typer) and
[lavyek](docs/benchmarks/lavyek.md) (it lives in a private repo). Their pages
explain the details and what coverage they would add back.

## Quick start

### Prerequisites

```bash
sudo apt install build-essential autoconf automake m4 pkg-config \
                 libgmp-dev libmpfr-dev libevent-dev libcurl4-openssl-dev \
                 libpcre3-dev zlib1g-dev libopenblas-dev liblapacke-dev \
                 libgsl-dev libsqlite3-dev libyaml-dev
```

This is the same list CI installs, so it is the one that is actually exercised on
a clean machine. Notably `liblapacke-dev` is separate from `libopenblas-dev` —
owl links `-llapacke`, and without it the build fails at link time with
`/usr/bin/ld: cannot find -llapacke`.

You also need opam 2.3+ and a switch with `dune` and `ocamlfind` (one is created
for you if needed).

### Setup

```bash
cd ~/macro-benches
make setup          # or: bash scripts/setup-monorepo.sh
```

This pulls the vendored packages, applies the source patches, builds the few
non-dune dependencies (pplacer, apron, rocq), and test-builds every binary. The
first run takes around ten minutes; later runs skip the steps that are already
done. It is idempotent, so you can rerun it any time without `make clean`.

#### dune compatibility

Verified with dune **3.22.1** and **3.24.0**.

dune 3.24 deleted the `coq` language extension ("The Coq Build Language has been
replaced by the Rocq Build Language"), and vendored rocq still declared
`(using coq 0.8)`. Because that is a *parse* error, it broke every build in the
workspace, not just rocq's — `dune build benchmarks/decompress/...` failed with
`Error: Extension coq was deleted in the 3.24 version of the dune language`.

Setup step 3b removes that declaration and the matching `(coq (flags ...))`
field from rocq's `dev` profile. Both are dead configuration here: no active
`dune` file under `duniverse/rocq` contains a `coq.theory` / `coq.pp` /
`coq.extraction` stanza, because rocq compiles its theories through its own
`tools/dune_rule_gen` (which emits plain `(rule (action (run rocq c ...)))`),
and the only files that would need the extension are two `dune.disabled` ones
that dune never reads. So the fix removes the declarations rather than porting
rocq to `(using rocq ...)`.

If you already have a populated `duniverse/`, rerun `make setup` to pick this
up — the step is skipped once applied.

### Run one benchmark by hand

Each benchmark has a build script that writes its binary to
`benchmarks/<tool>/<tool>-runtime`:

```bash
bash benchmarks/eio/eio.build.sh
./benchmarks/eio/eio-runtime
```

The build script assumes the compiler you want to measure is already on `PATH`
and writes its binary to `$RUNNING_OCAML_OUTPUT` (defaulting to
`<tool>-<runtime>` in the benchmark's own directory). See
[§Build-script contract](#build-script-contract).

Arguments matter — most benchmarks take an input file, an input size, or a rung
selector, so running a binary bare is a different benchmark from what the sweep
runs. Ask the manifest, which prints
*name, tool, script, timeout, expected exit, args*:

```bash
python3 scripts/ci-manifest.py list | grep -E '^(eio_conc_small|jsoo_small)\b'
```

The custom-`.ml` benchmarks can also be built straight from the dune workspace:

```bash
dune build -- benchmarks/eio/eio_bench.exe
./_build/default/benchmarks/eio/eio_bench.exe
```

### Run sweeps

For cross-runtime, frame-pointer, flambda, or GC-parameter sweeps you want an
orchestrator to manage the per-runtime switches. Point running-ng at the repo
(`export RUNNING_MACRO_BENCH_DIR=~/macro-benches`) and drive the sweeps from
there; see its docs for the available configs.

Which rungs run is selected by `RUNNING_TAG`:

| `RUNNING_TAG` | runs |
|---|---|
| *(unset)* | the `default` rung of every tool — the standard suite |
| `small_run` / `large_run` / `huge_run` | that size across every tool |
| `legacy` | the pre-ladder anchors, extra workloads, and frozen repros |
| `all_benches` | everything at once |

### Clean

```bash
make clean          # remove build artifacts, keep vendored sources
make clean-all      # remove everything generated (duniverse/, vendor/, _rocq_prefix/, _build*)
make setup          # repopulate from the lock file
```

### Build and run everything locally

The same two phases CI runs, driven off
[`benchmarks/manifest.yml`](benchmarks/manifest.yml) (the program list):

```bash
python3 scripts/ci-manifest.py check             # manifest vs. tree (seconds)
bash scripts/ci-build-all.sh                     # build every program (all rungs + legacy)
bash scripts/ci-run-all.sh                       # run the small rung of each tool once
ONLY="jsoo_small goblint_gen_small" bash scripts/ci-run-all.sh  # or just a few
```

CI builds everything (catching build breaks) but only *runs* the small rung of
each tool — flagged `ci_run: true` in the manifest — since the large rungs don't
fit a hosted runner.

When you add a benchmark, add it to the manifest in the same commit as its build
script — `check` fails if the two disagree, including when a new program is added
to a tool that already has a build script. See [CLAUDE.md](CLAUDE.md) §CI.

## How it works

1. Dependencies are locked once (`opam monorepo lock`) into
   `macro-benches.opam.locked`, which is committed.
2. `opam monorepo pull` downloads all of them into `duniverse/`. No solver, no
   `opam install`.
3. `setup-monorepo.sh` applies a handful of source patches for newer compilers
   and known upstream bugs. One of them keeps the workspace parseable by
   dune >= 3.24, which deleted the `coq` language extension that vendored rocq
   still declared — see "dune compatibility" below.
4. The few packages that aren't opam/dune (pplacer, apron, rocq) are vendored
   and built by their own scripts.
5. `dune build` compiles everything from local source with whichever compiler is
   on PATH, into a per-runtime `_build-<runtime>/` directory so different
   runtimes don't clobber each other.

## Build-script contract

A `benchmarks/<tool>/<tool>.build.sh` is called with the runtime's opam switch
already activated, so its compiler and `dune` are on `PATH`. It reads:

| Variable | Meaning | Fallback when unset |
|---|---|---|
| `RUNNING_OCAML_BENCH_DIR` | the benchmark's own directory (`benchmarks/<tool>/`) | the script's own directory |
| `RUNNING_OCAML_OUTPUT` | where to write the binary (absolute) | `<bench dir>/<tool>-<runtime>` |
| `RUNNING_OCAML_RUNTIME_NAME` | runtime tag, e.g. `ocaml-5.5.0` | `runtime` |
| `RUNNING_OCAML_SWITCH` | the active opam switch | unset |
| `RUNNING_OCAML_SWITCH_PREFIX` | that switch's prefix path | resolved from `RUNNING_OCAML_SWITCH`, else the `ocamlc` on `PATH` |

A script derives the monorepo root from its bench dir, builds into a per-runtime
`_build-<runtime>/`, and copies the result out. 

## Layout

```text
benchmarks/<tool>/   build script + input data (and driver .ml for custom benches)
docs/benchmarks/     one page per benchmark: what it runs and how to read it
scripts/             setup-monorepo.sh and the vendor-*.sh helpers
dune-overlays/       hand-written dune files for non-dune packages
duniverse/           vendored dependency sources          (generated, gitignored)
vendor/              manually vendored non-dune packages   (generated, gitignored)
macro-benches.opam.locked   the lock file                 (committed)
```

## More documentation

- [docs/benchmarks/](docs/benchmarks) has a page per benchmark.
- [CLAUDE.md](CLAUDE.md) has the operational detail beyond the build-script
  contract above:
  the in-process iteration and ring-size mechanics, the vendored-source patch
  table, the runtime-feature coverage matrix and known gaps, the backlog, and
  the gotchas worth knowing before you touch the build.
