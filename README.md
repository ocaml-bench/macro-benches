# macro-benches

A suite of real-world OCaml programs used as macro-benchmarks, for comparing one
OCaml runtime against another on workloads that look like the things people
actually run: compilers, provers, static analysers, a video pipeline, a key-value
store, and so on.

Every dependency is vendored into the repo with
[opam-monorepo](https://github.com/tarides/opam-monorepo), so every runtime
compiles byte-identical source. The only thing that changes between runs is the
compiler: if a number moves, the runtime moved it, not a different version of
some library that happened to get pulled in.

You can use it two ways:

- **Standalone.** Run `make setup` once, then build any single benchmark under
  any opam switch and run the binary yourself.
- **Orchestrated.** Point an orchestrator such as
  [running-ng](https://github.com/udesou/running-ng) at the repo and let it
  manage per-runtime switches and drive cross-runtime, frame-pointer, flambda or
  GC-parameter sweeps.

## The benchmarks

23 tools, 21 active (`merlin` and `lavyek` are disabled, see below). Each active
tool has an **input-size ladder**: `small` / `default` / `large` rungs (a couple
also `huge`) whose input is chosen so each reaches a different GC/runtime regime,
not just a bigger copy of the one below. A bare run executes the `default` rung
of every tool; other sizes are opt-in via a tag (see [Run sweeps](#run-sweeps)).
Older single-point benchmarks with their original anchors, extra per-tool
workloads, and the frozen issue reproducers are kept as **legacy** benches, run
only with `RUNNING_TAG=legacy`.

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
| [infer](docs/benchmarks/infer.md) | `infer_default` | Infer's multicore (domains) Java analysis of 215 classes of a real bytecode corpus: guava, byte-buddy, lucene, bcprov | Static analysis |

Two more tools ship in the tree but are currently disabled:
[merlin](docs/benchmarks/merlin.md) (an upstream race in the domains typer) and
[lavyek](docs/benchmarks/lavyek.md) (it lives in a private repo). Their pages
explain the details and what coverage they would add back.

`ocamlc-self-compile` is a 22nd benchmark directory belonging to the same
compiler tool as `ocamlc-compile-uucp`; its programs are legacy-only.

## Quick start

### Prerequisites

opam 2.3+ and a switch with `dune` and `ocamlfind` (one is created for you if
needed), plus the system libraries below.

Debian/Ubuntu:

```bash
sudo apt install build-essential autoconf automake m4 pkg-config zip python3-yaml \
                 libgmp-dev libmpfr-dev libevent-dev libcurl4-openssl-dev \
                 libpcre3-dev zlib1g-dev libopenblas-dev liblapacke-dev \
                 libgsl-dev libsqlite3-dev libyaml-dev
```

FreeBSD (as root):

```sh
pkg install bash git python3 autoconf automake libtool m4 pkgconf gmake gcc zip \
            gmp mpfr openblas lapacke gsl sqlite3 libyaml perl5 \
            curl libev libevent pcre py311-pyyaml
```

Notes on the FreeBSD list: `gmake` and `gcc` are both load-bearing (a few
vendored makefiles are GNU-only, and goblint needs a real GCC preprocessor);
zlib is in the base system; the PyYAML package name is versioned after your
`python3` and was renamed in 2024, so check `python3 -c 'import yaml'` rather
than trusting a spelling. `make setup` puts `/usr/local/include` and
`/usr/local/lib` on the C toolchain's search path; building a benchmark by hand
outside `make setup` may need the same:

```sh
export C_INCLUDE_PATH=/usr/local/include LIBRARY_PATH=/usr/local/lib
```

Set `LOCALBASE` if your packages are somewhere other than `/usr/local`. Several
suites need a source patch on FreeBSD; `make setup` applies them all. The
per-package reasoning, and the patch table, are in [CLAUDE.md](CLAUDE.md).

### Setup

```bash
cd ~/macro-benches
make setup          # or: bash scripts/setup-monorepo.sh
```

This pulls the vendored packages, applies the source patches, builds the few
non-dune dependencies (pplacer, apron, rocq), and test-builds every binary. The
first run takes around ten minutes; later runs skip the steps that are already
done. It is idempotent, so you can rerun it any time without `make clean`.

Verified with dune **3.22.1** and **3.24.0**. If you already have a populated
`duniverse/` and are moving to dune 3.24+, rerun `make setup`: one of the patches
is what keeps the workspace parseable there.

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
[Build-script contract](#build-script-contract).

Arguments matter: most benchmarks take an input file, an input size, or a rung
selector, so running a binary bare is a different benchmark from what the sweep
runs. Ask the manifest, which prints *name, tool, script, timeout, expected exit,
args*:

```bash
python3 scripts/ci-manifest.py list | grep -E '^(eio_conc_small|jsoo_small)\b'
```

The custom-`.ml` benchmarks can also be built straight from the dune workspace:

```bash
dune build -- benchmarks/eio/eio_bench.exe
./_build/default/benchmarks/eio/eio_bench.exe
```

### Run sweeps

For cross-runtime, frame-pointer, flambda or GC-parameter sweeps you want an
orchestrator to manage the per-runtime switches. Point running-ng at the repo
(`export RUNNING_MACRO_BENCH_DIR=~/macro-benches`) and drive the sweeps from
there; see its docs for the available configs.

Which rungs run is selected by `RUNNING_TAG`:

| `RUNNING_TAG` | runs |
|---|---|
| *(unset)* | the `default` rung of every tool, the standard suite |
| `small_run` / `large_run` / `huge_run` | that size across every tool |
| `legacy` | the pre-ladder anchors, extra workloads, and frozen repros |
| `all_benches` | everything at once |

### Build and run everything locally

The same three phases CI runs, driven off
[`benchmarks/manifest.yml`](benchmarks/manifest.yml) (the program list):

```bash
python3 scripts/ci-manifest.py check             # manifest vs. tree (seconds)
bash scripts/ci-build-all.sh                     # build every program (all rungs + legacy)
bash scripts/ci-run-all.sh                       # run the small rung of each tool once
ONLY="jsoo_small goblint_gen_small" bash scripts/ci-run-all.sh  # or just a few
```

CI builds all 95 programs (catching build breaks) but only *runs* the 20 small
rungs flagged `ci_run: true` in the manifest, since the large rungs do not fit a
hosted runner. There is a FreeBSD workflow alongside the Linux one.

When you add a benchmark, add it to the manifest in the same commit as its build
script: `check` fails if the two disagree, including when a new program is added
to a tool that already has a build script. See [CLAUDE.md](CLAUDE.md).

### Clean

```bash
make clean          # remove build artifacts, keep vendored sources
make clean-all      # remove everything generated (duniverse/, vendor/, _rocq_prefix/, _build*)
make setup          # repopulate from the lock file
```

## How it works

1. Dependencies are locked once (`opam monorepo lock`) into
   `macro-benches.opam.locked`, which is committed.
2. `opam monorepo pull` downloads all of them into `duniverse/`. No solver, no
   `opam install`.
3. `setup-monorepo.sh` applies a set of source patches for newer compilers,
   known upstream bugs, and platform differences.
4. The few packages that are not opam/dune (pplacer, apron, rocq) are vendored
   and built by their own scripts.
5. `dune build` compiles everything from local source with whichever compiler is
   on `PATH`, into a per-runtime `_build-<runtime>/` directory so different
   runtimes do not clobber each other.

Third-party versions all come from `sources.yml`, pinned to commits. Bumping one
is a one-line edit followed by `make setup`.

## Build-script contract

A `benchmarks/<tool>/<tool>.build.sh` is called with the runtime's opam switch
already activated, so its compiler and `dune` are on `PATH`. It reads:

| Variable | Meaning | Fallback when unset |
|---|---|---|
| `RUNNING_OCAML_BENCH_DIR` | the benchmark's own directory (`benchmarks/<tool>/`) | the script's own directory |
| `RUNNING_OCAML_OUTPUT` | where to write the binary (absolute) | `<bench dir>/<tool>-<runtime>` |
| `RUNNING_OCAML_RUNTIME_NAME` | runtime tag, e.g. `ocaml-5.5.0` | `runtime` |
| `RUNNING_OCAML_SWITCH` | the active opam switch | unset |
| `RUNNING_OCAML_SWITCH_PREFIX` | that switch's prefix path (optional; honoured if an orchestrator sets it) | resolved from `RUNNING_OCAML_SWITCH`, else the `ocamlc` on `PATH` |

A script derives the monorepo root from its bench dir, builds into a per-runtime
`_build-<runtime>/`, and copies the result out. `RUNNING_OCAML_OUTPUT` also
*selects the program* where one script backs several; see [CLAUDE.md](CLAUDE.md).

## Layout

```text
benchmarks/<tool>/   build script + input data (and driver .ml for custom benches)
benchmarks/manifest.yml     the program list                (committed)
docs/benchmarks/     one page per benchmark: what it runs and how to read it
scripts/             setup-monorepo.sh and the vendor-*.sh helpers
sources.yml          pinned versions of every third-party source
dune-overlays/       hand-written dune files for non-dune packages
duniverse/           vendored dependency sources          (generated, gitignored)
vendor/              manually vendored non-dune packages   (generated, gitignored)
macro-benches.opam.locked   the lock file                 (committed)
```

## More documentation

- [docs/benchmarks/](docs/benchmarks) has a page per benchmark.
- [CLAUDE.md](CLAUDE.md) has the operational detail beyond the build-script
  contract above: the CI phases, the in-process iteration and ring-size
  mechanics, the vendored-source patch table, the platform notes, the
  runtime-feature coverage matrix and known gaps, the backlog, and the gotchas
  worth knowing before you touch the build.
