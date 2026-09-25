# CLAUDE.md — working notes for agents & contributors on `macro-benches`

Auto-loaded context for Claude Code (and a reference for contributors). The
human-facing docs are `README.md` and the per-benchmark pages under
`docs/benchmarks/<name>.md`. This file holds the operational and machine-facing
detail that doesn't belong in either: the build-script contract, the CI phases,
the in-process iteration and ring-size mechanics, the system-prerequisite and
platform notes, the vendored-source patch table, the runtime-feature coverage
matrix and gaps, the gotchas, and the backlog.

## What this is

- A **dune monorepo** of real-world OCaml programs used as macro-benchmarks (coq,
  frama-c, goblint, alt-ergo, menhir, cpdf, owl, jsoo, irmin, liquidsoap,
  ocamlformat, decompress, eio, sedlex, yojson, zarith, pplacer, devkit, infer, …). All
  third-party deps are **vendored** under `duniverse/` (opam-monorepo), so every
  runtime compiles byte-identical source. 23 tools (21 active; `merlin` and
  `lavyek` disabled — see their doc pages). ocamlc counts as one tool but spans
  two benchmark dirs (ocamlc-self-compile + ocamlc-compile-uucp); `infer` is
  vendored manually (not opam-monorepo) — see its doc page and the patch table.
- **Input-size ladder + tags.** Each tool has `small`/`default`/`large` (a few
  also `huge`) rungs whose input reaches a different GC/runtime regime, not just a
  scaled-up copy. The selection lives in running-ng's `macro_base.yml` `tags:`
  (`default_run`/`small_run`/`large_run`/`huge_run`/`legacy`/`all_benches`); a bare
  run auto-applies `default_run`. **Legacy** = the pre-ladder anchors, extra
  per-tool workloads, and frozen issue reproducers (`liq_video_frames_pool` #14533,
  `goblint` #13733) — kept, run only with `RUNNING_TAG=legacy`. In THIS repo the
  same split is in `benchmarks/manifest.yml`: all 95 programs listed (build-all),
  the 20 small rungs flagged `ci_run: true` (what CI runs, via `ci-manifest.py
  list-run`). The `knob-a-rungs` branch name is historical — docs say "input-size
  ladder".
- Driven by `~/running-ng` (suite type `OCamlBenchmarkSuite`, **not** the
  satellite-switch path): each benchmark has `benchmarks/<tool>/<tool>.build.sh` that
  runs `dune build` with the runtime compiler on PATH, into a **per-runtime build dir**
  `_build-<runtime>`, then copies/links out the binary `benchmarks/<tool>/<prog>-<runtime>`.

## Hard rules (do not violate)

- **Do not comment on PRs, or add to PRs, unless explicitly asked to.**
- No "Claude"/Anthropic/Co-Authored-By: Claude in further commit messages.
- **Remote is `origin = github.com/ocaml-bench/macro-benches`** — a *shared org*
  repo, not a personal fork. Be careful pushing; commit/push only when asked.
- **Never delete an individual file inside a `_build-<runtime>/` tree** to "force a
  rebuild" — it corrupts dune's incremental state (you'll get `*.impl.d: No such file`
  / missing `.sexp`). To force a re-probe/rebuild, remove the **whole**
  `_build-<runtime>` dir (or `dune clean`), and delete the benchmark's **output**
  binary so running-ng rebuilds it.
- **Don't commit `_build-*/`, `_rocq_prefix/`, big inputs, or vendored-source churn**
  casually. `duniverse/` is generated (opam-monorepo); regenerate via `scripts/`.
- Keep this file consistent with every commit. For `README.md` and
  `docs/benchmarks/<name>.md`, follow the docs rule below.
- **Human-facing docs are written by a human.** `README.md` and every other
  `.md` file except this one are maintained by hand. When a change calls for a
  docs update, do not edit the prose. Put an invisible HTML comment next to the
  passage that needs to change, saying what changed and what the text should
  now say: `<!-- TODO(docs): ... -->` (it does not render). When a PR is being
  prepared, list every such comment so they can be resolved by hand before
  merge: `grep -rn 'TODO(docs)' --include='*.md' .`
- **Comments only where the code is not self-explanatory.** Never add a comment
  that restates the code. Where one is needed, keep it short and explain the
  intent or the non-obvious constraint at a high level, for a human reader.

## Where things live (read first)

- `benchmarks/<tool>/` — `<tool>.build.sh` (called by running-ng) + input data.
- `benchmarks/manifest.yml` — **the program list**: name → tool, build script, args.
  Needed because several build scripts derive their dune target from the *output
  filename*, so the scripts alone don't say what programs exist. CI reads this.
- `docs/benchmarks/<name>.md` — human-facing page per benchmark.
- `duniverse/` — vendored dependency sources (the actual compiled code).
- `vendor/` — manually vendored bits (camlpdf, cpdf-source, zarith, pplacer, frama-c, apron, …).
- `scripts/` — `setup-monorepo.sh`, `vendor-*.sh` (coq, apron, frama-c, cpdf, …),
  `ci-build-all.sh` / `ci-run-all.sh` / `ci-manifest.py` (the CI phases).
- `.github/workflows/ci.yml` — master-only build + run-once gate (see §CI).
- `.github/workflows/ci-freebsd.yml` — the same gate on FreeBSD, in a VM; a
  measurement rather than a gate for now (see §CI).
- `sources.yml`, `macro-bench-*.opam(.template)`, `dune-workspace`, `dune-overlays`.
- `_build-<runtime>/` — per-runtime dune build output (gitignored).

## Build / run

`README.md` §Build-script contract states the variable table for humans and
points here for everything below — keep the two in sync.

running-ng calls `<tool>.build.sh` with the runtime compiler on PATH and these
env vars:

| Variable | Meaning | Fallback when unset |
|----------|---------|---------------------|
| `RUNNING_OCAML_BENCH_DIR` | Directory with this benchmark's sources (`benchmarks/<tool>/`) | the script's own directory |
| `RUNNING_OCAML_OUTPUT` | Path where the built binary must be written | `${BENCH_DIR}/<tool>-${RUNTIME_NAME}` |
| `RUNNING_OCAML_RUNTIME_NAME` | Runtime identifier (e.g. `ocaml-5.4.1`) | `runtime` |
| `RUNNING_OCAML_SWITCH` | Opam switch name (when applicable) | unset |
| `RUNNING_OCAML_SWITCH_PREFIX` | Prefix of the runtime's switch. Only `ocamlc-self-compile`, `ocamlc-compile-uucp` and `jsoo` need it — they run the runtime's *own* `ocamlc` / `ocamlc.byte` as the workload, so they need the switch, not just a compiler on PATH | `opam var prefix --switch "$RUNNING_OCAML_SWITCH"` when that is set, else the `ocamlc` on PATH |

A script first clears the ambient `OPAM_SWITCH_PREFIX`,
`OCAMLTOP_INCLUDE_PATH`, `CAML_LD_LIBRARY_PATH`, `OCAMLLIB` and `OCAMLPATH` so a
previously active switch can't contaminate the build with its `.cmi`s (the few
benchmarks needing a library path — goblint's apron, coq's rocq prefix — set
`OCAMLPATH` themselves afterwards), then `dune build --root <monorepo>
--build-dir _build-<runtime> --profile release <target>` and copies the result
out. Because every benchmark lives at `benchmarks/<tool>/`, each script derives
the monorepo root from `BENCH_DIR` (`$(cd "${BENCH_DIR}/../.." && pwd)`); no
macro-specific env var is needed, and the contract matches `~/benches/`
name-for-name. (`RUNNING_MACRO_BENCH_DIR` is a *run*-time variable — the
manifest's `args` interpolate it to reach input files — not a build-time one.)

Because `_build-<runtime>` is keyed by the runtime tag, two runtimes never
clobber each other; benches shares one `_build/` per benchmark across runtimes,
so switching runtime there rebuilds from scratch.

**`RUNNING_OCAML_OUTPUT` selects the program**, not just the destination. Where
one script backs several programs (`eio.build.sh` → `eio_fiber_stream` + the
`eio_conc_*` ladder; `ahrefs-devkit.build.sh` → seven; also cpdf, goblint, jsoo,
pplacer, ocamlc-compile-uucp) they differ in *dune target*, and the script cases
on `basename "${OUT}"` (or `BM_NAME`, that basename minus the runtime suffix) to
pick it. This is the one place the contract is load-bearing beyond "write the
binary here" — benches has no equivalent, because programs sharing a script there
build the same binary and differ only in the config's arguments. `ci-manifest.py
check` only cross-checks the `case "${BM_NAME}"` / `case "${OUT_BASE}"` form
(ahrefs-devkit today); a `case "$(basename "${OUT}")"` block is invisible to it.

**Generated inputs are the build script's job** — there is no
`<name>.build.deps.sh` split as in benches. alt-ergo's `fill_x100.why` and
congruence chains, goblint's state machines, ocamlformat's line ladder and jsoo's
replicated sources are generated in the build script, skipped if already present,
and gitignored. Runtime-independent ones are generated once and shared by every
runtime in a sweep; the ones that must be built *by the runtime under test*
(jsoo's and `ocamlc-compile-uucp`'s bytecode) carry the runtime tag in their
filename instead. Manifest entries whose `args` name such a file need
`inputs_generated: true` (see §CI check 4).

Outputs come in two shapes — copied binaries and wrapper scripts that `exec` into
`_build-<runtime>/`. Both satisfy the contract; see §Gotchas before deleting a
build directory by hand.

Standalone usage (no running-ng): set `RUNNING_MACRO_BENCH_DIR=~/macro-benches` and
drive `~/running-ng`'s `build_ocaml_binaries_gc_sweep.sh` / `run_ocaml_bench_gc_sweep.sh`.
Or drive the build straight from the manifest: `bash scripts/ci-build-all.sh`.

## CI

`.github/workflows/ci.yml` runs on **pull requests into `master`** and on **pushes
to `master`** (plus a weekly cron and `workflow_dispatch`); nothing runs on other
branch pushes. The PR run is the gate; the post-merge run exists because the
required check is not `strict`, so two PRs can each be green against an older
`master` and still break it together — without a push run, nothing would notice
until the next PR or the Monday cron. It is cheap (same cache key as the PR run
that just passed) and it refreshes the cache in `master`'s scope, which is the only
scope every PR can restore from. Note `cancel-in-progress` is deliberately limited
to PR runs: superseding a PR run is right, but cancelling a `master` run would
leave the merge that triggered it unverified.

Two matrix legs: the
**latest stable release**, which gates, and the **`ocaml/ocaml` trunk tip**, which
is `continue-on-error` because it tracks a moving compiler and needs ppxlib/lwt
git `main` (patches 4+5 below). The trunk leg resolves the tip commit *before*
creating the switch and folds the SHA into every cache key — otherwise a restored
opam-root cache silently tests a stale trunk.

The gate is enforced by branch protection on `master`: the required check is
`build + run once (stable)`. The matrix `label` is deliberately version-free —
GitHub matches required checks **by name**, so putting `5.5.0` in the label would
orphan the requirement the moment the compiler is bumped.

Before those, two suites that cost under a second: `scripts/tests/
test-lib-portable.sh` and `test-build-scripts-portable.sh`. The first asserts every
helper in `lib-portable.sh` is byte-identical to the GNU command it replaces, which
**requires GNU userland** — on FreeBSD those comparisons are skipped and it reports
14 checks where Linux reports 24. So the FreeBSD job cannot cover for the Linux one
or vice versa; both run both. The second is static (it checks every build script
sources `lib-portable.sh`), which matters because the LOCALBASE export that line
carries is gated off on Linux: a script that stops sourcing it breaks only on
FreeBSD, and only this check sees it here.

Three phases, all driven off `benchmarks/manifest.yml`:

- `scripts/ci-manifest.py check` — runs first because it costs seconds. It compares
  **sets**, not just counts, in five directions:
  1. every manifest program's tool dir and build script exist;
  2. every `benchmarks/*/*.build.sh` is claimed by a program or listed under
     `disabled:` — this is what catches a whole new benchmark landing with no
     manifest entry;
  3. a build script that dispatches on the program name (`case "${BM_NAME}"`, i.e.
     ahrefs-devkit today) accepts *exactly* the programs the manifest claims for it
     — this is what catches a new program added to an **existing** tool, where the
     build script already exists so (2) stays quiet. Both directions are errors: a
     `case` arm with no manifest entry, and a manifest entry the `case` would reject
     with `Unknown benchmark`;
  4. every in-tree input path in a program's `args` exists, so a program can't be
     added without committing its input. Generated inputs opt out with
     `inputs_generated: true` — the `alt_ergo_{fill,chain_small,chain_default,
     chain_large}` and `ocamlformat_rocq_{small,default,large}` entries, whose
     `.why`/`.ml` inputs are built by their build script and gitignored, so a
     fresh checkout does not have them. Benchmarks that generate inputs but take a
     rung *selector* rather than a path (goblint, jsoo) need no flag: the check
     only looks at in-tree paths in `args`;
  5. one `docs/benchmarks/<tool>.md` per tool, both directions.

  It prints the counts it compared (`24 benchmark directories = 22 with programs
  + 2 disabled`, `95 programs`, `24 docs pages`) so the log shows the numbers,
  then lists every problem it found rather than stopping at the first. (21 not 20
  because the compiler tool spans two directories: ocamlc-self-compile and
  ocamlc-compile-uucp.)

- `scripts/ci-build-all.sh` — builds every program into `_build-ci`. Deletes the
  output binary first, so a stale wrapper can't make a build look successful (the
  `exit 127` trap in §Gotchas).
- `scripts/ci-run-all.sh` — runs each program once, with its manifest args, from a
  fresh scratch cwd so relative outputs (menhir's `--base`, goblint's
  `witness.yml`) don't land in the tree.

Neither stops at the first failure: a hermeticity break usually takes several
benchmarks with it, and one run should show all of them. Both write a table to
`$GITHUB_STEP_SUMMARY` and leave per-program logs in `ci-logs/`.

Notes for whoever touches this next:

- **`args` in the manifest are copied verbatim from running-ng's `macro_base.yml`**
  so the two lists can be diffed mechanically. Keep it that way.
- **`expected_exit`** declares a by-design non-zero exit. Only `alt_ergo_unsat_smt2`
  needs it today: `--timelimit 15` means the workload *is* "solve for 15 s", the goal
  never closes, and alt-ergo dies of its own SIGVTALRM (128+14 = **142**) on every
  run. Don't "fix" that by dropping the flag — the time limit is the workload.
- **In the manifest rows, `args` is the last column on purpose.** Bash treats TAB as
  whitespace-IFS, so an empty field mid-row collapses and shifts every later column;
  the programs with no args would silently take the next field as their argv.
- **Ladder rungs are deliberately absent.** The base rung is the signal CI needs,
  and the big rungs don't fit a hosted runner (sedlex's large rung peaks near
  27 GB RSS). When rungs land on master, list only the `_small` one.
- **`SKIP_TEST_BUILD=1`** makes `setup-monorepo.sh` skip its `[9/9]` test build.
  CI sets it because that step targets the default `_build/` while the build
  scripts target `_build-<tag>/` — running both compiles the duniverse twice.
- **Dune is pinned per leg**: `3.22.1` on stable, git `main` on trunk (released
  dune can't bootstrap against 5.6). Patch 19 is what lets the trunk leg work at
  all — its dune is ≥ 3.24, which deleted the `coq` extension vendored rocq
  declared. The stable pin is for determinism, not necessity: the workspace parses
  under both 3.22.1 and 3.24 now, and pinning keeps the build environment fixed
  the same way every source is pinned.
- The **weekly cron run skips the cache** on purpose. Everything is pinned now
  (see §Vendored source pins), so this is not a drift detector — it is a check
  that a *cold* setup still works: that every pinned commit and tarball is still
  fetchable, that the rocq bootstrap works from nothing, and that the cache we
  rely on the rest of the week isn't hiding a broken setup path.

### FreeBSD (`.github/workflows/ci-freebsd.yml`)

The same three phases on FreeBSD 15.1, the release the port was validated on
(95/95 by hand). GitHub has no FreeBSD runners and Cirrus CI, which had native
ones, **shut down 2026-06-01**, so this runs `vmactions/freebsd-vm` (pinned to a
commit) inside a Linux runner. `/dev/kvm` is present on `ubuntu-latest`, so the
guest is hardware-accelerated rather than emulated; VM boot is ~3.5 min.

Its steps **deliberately mirror `ci.yml` name for name and in order**, so the two
can be read side by side and drift is visible. What differs, and why:

- three extra steps at the front (report virtualisation support, free host disk,
  boot the VM) with no Linux counterpart;
- `ocaml/setup-ocaml@v3` becomes `Set up the OCaml switch`, because that action is
  a GitHub Action and does not run inside the VM;
- `pkg` replaces `apt`, with README's shorter FreeBSD list (zlib and the C
  toolchain are in the base system; nothing uses PCRE2). **`gmake` is not
  optional** — camlidl's and camlzip's Makefiles use GNU conditionals bmake
  rejects as a syntax error. opam is packaged as `ocaml-opam`.
- `sync: nfs`, not the default rsync: the VM persists and every step runs in it
  via `shell: freebsd {0}`, and rsync would copy the whole workspace in and back
  around *each* step.

**It gates**, on the same terms as `ci.yml`: the stable leg is required, the
trunk leg is `continue-on-error` because it tracks a moving compiler. Triggers
match too (PR, push to master, weekly cron staggered an hour after ci.yml's).
Measured at **26.9 min stable / 31.2 min trunk**, against ~35 for Linux, with
`Build every benchmark` at 16.2 min being the bulk.

**No cache, deliberately.** `ci.yml` caches `duniverse/`, `vendor/` and
`_rocq_prefix/` because there they sit on local disk next to the runner. Here the
build runs inside the VM while `actions/cache` runs on the host, so everything
cacheable has to cross the NFS mount twice per run: ~2.7 GB (those three plus a
from-source opam root) restored and saved, to avoid 4.5 min of work, 17% of the
job. The much smaller checkout copy already costs 0.3-1.1 min across that mount,
so it is at best a wash. Revisit only if the build phase itself becomes
cacheable, since at 16 min that is what actually dominates. `OPAMROOT` is
`/opamroot`, outside the workspace, for the same reason.

Note the required check has to be enabled in branch protection separately;
adding the leg here does not make it required.

## System prerequisites, and why each one is there

README lists the apt and pkg lines. What it deliberately does not carry:

- **The apt list is not byte-identical to CI's.** `ci.yml` omits `zip`, because a
  stock GitHub runner already ships it. `zip` is needed by
  `scripts/vendor-infer-corpus.sh` (without it infer's corpus step fails with
  `zip: command not found`), so it stays in README's list: a minimal container can
  hit what a hosted runner cannot. Do not "resync" the two by deleting it.
- **`liblapacke-dev` is separate from `libopenblas-dev`.** owl links `-llapacke`;
  without it the build fails at link time with `cannot find -llapacke`.
- **`python3-yaml` (PyYAML) is not `libyaml-dev`.** The first is the Python module
  `scripts/ci-manifest.py` imports, the second is frama-c's C library. Both lists
  carry both because a stock GitHub runner happens to ship PyYAML while a minimal
  container or a fresh FreeBSD host does not.
- **No PCRE2 anywhere.** `conf-libpcre2-8` used to sit in
  `macro-bench-devkit.opam.template`, but nothing in the tree has ever used PCRE2:
  devkit depends on the `pcre` OCaml library (PCRE **1**, via `conf-libpcre`),
  there is no `Pcre2.` under `duniverse/`, and the apt list only ever installed
  `libpcre3-dev`. On CI the requirement was satisfied by accident, because
  `libgio-2.0-dev` and `libselinux1-dev` drag `libpcre2-dev` in. It has been
  dropped from the template and the lock; do not put it back.

### FreeBSD

- **Base clang searches neither `/usr/local/include` nor `/usr/local/lib`.** Its
  default include list is only `/usr/lib/clang/<v>/include` and `/usr/include`, so
  a vendored C stub that includes a pkg-installed header fails with
  `fatal error: 'gsl/gsl_vector.h' file not found` even though the package is
  installed. `scripts/lib-portable.sh` exports `LOCALBASE` and puts both on the
  search path; that export is gated off on Linux, which is why
  `scripts/tests/test-build-scripts-portable.sh` statically asserts every build
  script sources `lib-portable.sh`: a script that stops doing so breaks only on
  FreeBSD, and only that check sees it here.
- **`gmake` is not optional.** camlidl's and camlzip's Makefiles use GNU
  conditionals that bmake rejects as a syntax error, so `scripts/vendor-apron.sh`
  calls `gmake` where available.
- **`gcc` is needed even though base clang builds everything else.** goblint is the
  exception: CIL rejects a preprocessor whose `--version` mentions clang, which on
  FreeBSD is `/usr/bin/cpp`. See patches 29 and 30; without a real GCC the
  analysis aborts at **run** time with
  `Failure("No good preprocessor (cpp) found")`, long after everything has built
  cleanly.
- **No zlib package.** FreeBSD ships it in the base system.
- **The PyYAML package name has two moving parts:** it is versioned after your
  `python3` (`py311-` for 3.11), and the port was renamed `devel/py-yaml` to
  `devel/py-pyyaml` in 2024, so older releases spell it `py311-yaml`.
  `ci-freebsd.yml` derives the name and then verifies `python3 -c 'import yaml'`
  rather than asserting a spelling. Do the same by hand.
- Five suites need a source patch on FreeBSD, all applied by `make setup`: devkit
  (25), owl (26), pplacer (27), and goblint (29 and 30, plus its apron chain
  needing `gmake`). Note **28 is not a FreeBSD patch**, despite sitting in that
  run of numbers.

## Vendored source pins

`sources.yml` is the single source of truth for every third-party version this
repo vendors, and `scripts/lib-sources.sh` is how the scripts read it:

- `src_field <key> <field>` — one field out of `sources.yml`. Deliberately awk, not
  PyYAML, so setup still works on a machine with only bash, git, curl and a
  compiler.
- `clone_pinned <key> <dir>` — clone a git source at its pinned commit. Idempotent
  (no-op when the checkout is already at the pin), and it *re-clones when the pin
  moves*, which the old "does the directory exist?" checks could not detect. It
  keeps `.git`, so `git -C <dir> rev-parse HEAD` tells you what you have.

Nothing tracks a branch HEAD any more. Six sources used to — ppxlib, lwt, merlin,
js_of_ocaml, pplacer, mcl — which meant a cold `make setup` vendored whatever
upstream had that morning, silently changing the benchmark binaries and therefore
the measurements. When they were pinned, ppxlib had already drifted 7 weeks past
the validated tree and lwt 3 months; the js_of_ocaml branch had been squashed and
deleted upstream, so a cold clone failed outright.

Consequences worth knowing:

- **js_of_ocaml is pinned to a `master` commit**, not the old `ocaml-5.6` PR
  branch: the 5.6 support landed on master (the `[ 5; 7 ]` bound in
  `compiler/lib/magic_number.ml`) and the branch is gone. Bumping this pin changes
  *two* benchmarks — `ocamlc_self_compile` takes its workload from
  `duniverse/js_of_ocaml/benchmarks/sources/ml`.
- **Pins are commits, never tags.** A tag can be re-pointed upstream. Resolve one
  with `git ls-remote <url> 'refs/tags/<t>^{}'`, which gives the commit; plain
  `refs/tags/<t>` gives the *tag object* for an annotated tag, which is a
  different sha. `clone_pinned` peels a tag-object pin (`_peel_commit`) and
  carries on with a note, because the tag object is immutable too — so the pin is
  still a pin. Prefer the commit anyway: it is what `rev-parse HEAD` will show
  you. Getting this wrong used to fail the *whole* checkout with `checked out
  <sha>, expected <sha>`, and the half-vendored tree it left behind was then
  mis-built by the next caller.
- **`clone_pinned` tries three fetches**: the commit directly (GitHub allows it);
  else the recorded branch/tag shallow, then verifies the commit matches (GitLab
  refuses bare commits — this is the frama-c path, and it is still pinned because
  a moved ref fails the verify: the pinned commit is not in the shallow object
  store, so there is nothing to peel and the compare is against the raw pin);
  else a full clone.
- **`ci-manifest.py check` enforces this**: every `src_field`/`clone_pinned` key
  must exist in `sources.yml` with the fields it asks for, every `commit:` must be
  full 40-hex, and **no script may call `git clone` directly** (only
  `lib-sources.sh`, for the fallback). That last rule is what stops an unpinned
  clone creeping back in.
- Bumping a pin is a one-line edit to `sources.yml` plus `make setup`. It shows up
  in review and CI rebuilds and re-runs everything against it — which is the
  entire point.

## Gotchas (hard-won — don't rediscover)

- **Two kinds of output binary.** Some `<prog>-<runtime>` are **standalone copied
  binaries** (menhir, cpdf, alt-ergo, …); others are **tiny wrapper scripts** that
  `exec` the real `.exe` *inside* `_build-<runtime>/…` (coqc, owl, devkit, jsoo,
  goblint, frama-c, pplacer, liq_video_frames, …). Deleting `_build-<runtime>` leaves
  the wrappers in place, so running-ng thinks they're built, **skips rebuild, and the
  wrapper fails at run with `exit 127, .exe: No such file`** — *not* an MMTk/runtime
  bug. Re-`buildbms` after deleting the wrapper output to regenerate the `.exe`.
- **dune caches configurator probes in `_build`** (e.g. `lwt_features.h`, `*.sexp`).
  An env-var change (e.g. `LIBRARY_PATH`) alone won't re-probe — needs a clean build dir.
- **The duniverse builds across multiple compilers** (5.4.1, `d8bb46c`, trunk,
  5.5.0-rc1, ocaml-mmtk). All programs build on stock 5.5.0-rc1.
- **External C deps:** apron (goblint) needs camlidl + gmp/mpfr; owl needs
  openblas/cblas; cpdf needs camlpdf; these come via `vendor/` + `scripts/vendor-*.sh`.
- **Under ocaml-mmtk** (built via running-ng's `OCamlMMTk`): all 31 *build* (the
  runtime supplies `LIBRARY_PATH`+heap), but a few **crash at run** — see MMTk notes.
- **infer's `extlib`/`camlzip` duplicate-hide window.** javalib/sawja link `extlib` +
  `zip` from infer's per-runtime prefix, but the duniverse *also* ships them (devkit
  depends on both) and dune rejects two libraries with the same public name. The clash
  is only visible while the prefix is on `OCAMLPATH`, so `infer.build.sh` hides
  `duniverse/{ocaml-extlib,camlzip}` for the duration of its dune build and restores
  them via an EXIT trap. Consequence: **don't build infer and devkit concurrently in
  the same tree** — the hide window would break a parallel devkit build. running-ng's
  sequential `buildbms` is fine.
- **infer's overlay links `ounit2`, not `oUnit`.** Infer's upstream-generated dune links
  the legacy findlib alias `oUnit` (which a normal opam switch provides via the
  transitional `ounit` package); the hermetic duniverse ships only the `ounit2` public
  name, so `dune-overlays/infer/.../{clang,unit}/dune` + `src/dune` link `ounit2` (same
  library). This is why infer built piecewise on a full macOS switch but not hermetically
  until the overlay was fixed.

## Per-session workflow

1. Identify which benchmark/tool you're touching; its build glue is
   `benchmarks/<tool>/<tool>.build.sh`; its source is under `duniverse/` or `vendor/`;
   its human doc is `docs/benchmarks/<tool>.md`.
2. Build via running-ng with `RUNNING_MACRO_BENCH_DIR` set; don't hand-delete `_build`
   internals.
3. Commit only when asked; don't commit build output.

---

## Iteration counts (in-process loops)

A few benchmarks have per-invocation work that's too short to measure reliably —
startup overhead dominates and observability tools (olly, perf) lose precision.
Two patterns are in use.

**Shell-loop wrapper** (legacy, *broken for olly*). Some build scripts generate a
wrapper that runs the binary `N` times in a shell loop (`for _ in $(seq 1 N); do
"$REAL_EXE"; done`). This works for wall-time aggregation but breaks olly's
runtime_events attach model: olly sees one OCaml process at a time. With short
per-child work the events files stack in `/tmp` and olly aggregates them; with
longer per-child work (e.g. `pplacer_testsuite` at ~3.5 s/child) olly attaches to
the first child only and silently misses the other N−1.

**Env-var / argv in-process loop** (recommended). The OCaml entry point reads a
count and runs the work N times inside the same process; the wrapper just sets the
count and `exec`s the binary. The orchestrator's positional arg becomes the loop
count, one process does N iterations, olly observes the whole thing.

In use by:

| Benchmark | Count via | Notes |
|---|---|---|
| `pplacer_testsuite` | `PPLACER_TEST_LOOP` env var | OUnit runner; env var avoids clashing with OUnit's argv parsing |
| `owl_gc` | `Sys.argv.(1)` | plain main; argv otherwise unused (default 1) |
| `devkit_stre` | `Sys.argv.(1)` | loops the 8 sub-benches (default 1) |
| `devkit_gzip` | `Sys.argv.(1)` | same shape as stre |
| `devkit_network` | `Sys.argv.(1)` | same shape as stre |
| `liq_video_frames_pool` | `Sys.argv.(1)` | number of frames (repetition); `argv.2`/`argv.3` = frame width/height (input size = resolution) |

Note: `devkit_htmlstream` is **not** in this list — it runs fixed internal
`for _ = 1 to 10` loops and is copied out as a standalone binary, so it ignores
`Sys.argv`. (The top summary table in older READMEs over-generalised this.)

**Ring-size interaction.** One process accumulating events across N iterations
needs a bigger `runtime_events` ring than N separate processes. For
allocation-heavy benches (owl_gc especially) large counts overflow the ring and
olly reports lost events plus a corrupted `wall_time`. Convention: `re-25` (32 MB)
for the in-process-loop benches; bump to `re-26` (64 MB) if a new one hits the
limit. Empirical owl_gc sizing: `re-23` (8 MB) starts corrupting `wall_time` at
arg 5; `re-25` is clean through arg 6 (~16s), the current setting.

When porting a benchmark to this pattern: wrap the entry point with a count
(default 1; env var if it already parses argv, else `Sys.argv.(1)`), drop the
shell `for` loop in the build script, set the orchestrator `args:` to the count,
and if the entry point is upstream code record the patch in `setup-monorepo.sh` so
it survives a re-vendor.

## MMTk (`ocaml-mmtk`) notes

Built via running-ng's `OCamlMMTk` runtime type (OCaml 5.5 + the MMTk collector).
Of the 31 non-infer programs all build and 27 run cleanly under both native plans
(Immix, StickyImmix); `infer` has been validated on stock 5.4.0 + 5.5.0 but **not**
yet under MMTk (its `--multicore` shared-heap parallelism is untested there). Known
MMTk-only issues:

- **Crashes (4 programs).** `alt_ergo_{fill,yyll,unsat_smt2}` SIGSEGV (the moving
  collector relocates a value a C stub holds a raw pointer to, via zarith→GMP; runs
  fine under a non-moving MMTk build, so it's a moving-GC / object-pinning gap) and
  `pplacer_testsuite` SIGABRT (a channel finaliser locks an already-closed channel
  mutex during GC). Both are excluded from the running-ng MMTk configs.
- **Off-heap is not GC-paced.** `MMTK_HEAP_SIZE_MB` bounds only on-heap memory.
  Custom-block off-heap data (Bigarray bulk data in `owl_gc`, GMP limbs in
  `zarith_pi`) is freed by the block's finaliser only when the proxy is collected,
  but MMTk paces on on-heap occupancy, so off-heap bytes accumulate with the heap
  budget: `owl_gc` RSS goes from ~130 MB at a 3 MB heap to ~12 GB at a 16 GB heap
  with the same live set. Stock OCaml paces the major GC on off-heap memory via
  `caml_alloc_custom_mem`; under MMTk that path is currently inert. These benches
  are poor footprint signals under MMTk.

## Benchmark quick-reference cross-table

| Benchmark | wall (s) | gc% | Allocation profile | Strongest signal for |
|---|---|---|---|---|
| `coqc_corelib_stress` | 17 | 94 | minor-saturation | minor-GC fast path (mixed fib/ack/tree; old 52s stale) |
| `coqc_tree_small` | 5.3 | 90 | minor-saturation (D=17, 0.57GB) | minor-GC fast path (input size = make_tree depth) |
| `coqc_tree_default` | 19 | 94 | minor-saturation (D=18, 0.98GB) | as small, deeper reduction |
| `coqc_tree_large` | 69 | 97 | minor-saturation (D=19, 1.89GB, 64ms max pause) | minor-GC saturation at scale (highest gc% in suite) |
| `eio_fiber_stream` | 6 | 10 | promotion-heavy | OCaml 5 effects, fiber scheduler |
| `eio_conc_small` | 5.7 | 62 | live fibers+buffers (3000 pairs, 0.69GB) | input size = concurrency degree (eio_conc_bench: N indep fiber pairs) |
| `eio_conc_default` | 17 | 63 | live set (9000 pairs, 1.99GB) | as small, more concurrent pipelines |
| `eio_conc_large` | 41 | 63 | live set (21000 pairs, 4.96GB, max pause 76ms) | promotion-bound (promo 0.85); read by RSS/top_heap |
| `irmin_mem_rw` | 12 | 11 | medium | Lwt, persistent hash-tree (repetition, 3000 keys + 20000 ops) |
| `irmin_mem_rw_small` | 5 | 20 | churn (6000-key store, 31MB) | Lwt + persistent-hash-tree churn (input size = store size; O(n_keys²) write) |
| `irmin_mem_rw_default` | 16 | 25 | churn (10000-key store, 44MB) | as small, more churn |
| `irmin_mem_rw_large` | 52 | 29 | churn (18000-key store, 74MB) | hash-tree/Hashtbl churn at scale (RSS small; churn ladder, gc% rises) |
| `liq_parse_typecheck` | 26 | 22 | promotion-heavy (48%) | AST + minor-to-major copy (repetition, 50000× fixed script) |
| `liq_parse_typecheck_small` | 5 | 59 | promotion-heavy (0.22, 0.26GB) | parse+typecheck AST/type-env at scale (input size = script size, generated units) |
| `liq_parse_typecheck_default` | 14 | 60 | promotion-heavy (0.44GB) | as small, bigger AST + type env |
| `liq_parse_typecheck_large` | 64 | 59 | promotion-heavy (12k units, 0.72GB) | promotion + type-inference throughput at scale (~60% gc%, super-quadratic wall) |
| `ydump_repeat` | 5.5 | 4.5 | promotion-heavy (65%) | recursive variants, JSON tree |
| `ydump_repeat_small` | 5.5 | 29 | promotion-heavy (28%, 3.25GB) | promotion + major-GC pauses on a boxed JSON tree (input size = doc size) |
| `ydump_repeat_default` | 16 | 34 | promotion-heavy (10GB) | as small, bigger tree |
| `ydump_repeat_large` | 33 | 40 | promotion-heavy (1.5GB doc, 20GB, 424ms max pause) | promotion throughput + largest major-GC pauses in suite (pointer-dense tree) |
| `test_decompress` | 5 | 2.4 | promotion-heavy + Bigstring | Bigstring header allocation |
| `test_decompress_small` | 5 | 0.8 | compute + Bigstring (80MB payload, 0.5GB) | DEFLATE codegen/compute (least GC-bound bench; input size = payload size) |
| `test_decompress_default` | 16 | 0.8 | compute + Bigstring (256MB, 1.4GB) | as small, bigger payload |
| `test_decompress_large` | 63 | 0.9 | compute + Bigstring (1GB, 5.7GB) | pure DEFLATE compute/codegen at scale (compute-bound control) |
| `pplacer_testsuite` | 13 | 70 | major-heavy (FFI) | gsl/sqlite3, tree allocation |
| `pplacer_like_small` | 4.7 | 0.6 | off-heap GSL Glv (0.22GB, 17.6k sites) | input size = likelihood n_sites (Felsenstein + ML pendant scan) |
| `pplacer_like_default` | 15 | 0.6 | off-heap GSL Glv (0.65GB, 55k sites) | as small, bigger alignment |
| `pplacer_like_large` | 51 | 0.6 | off-heap GSL Glv (2.18GB, 187k sites) | compute-bound; gc%~0, read by RSS/alloc_words |
| `owl_gc` | 16 | 50 | off-heap (Bigarray, small) | Bigarray finalisation, OpenBLAS stubs |
| `owl_gc_small` | 4 | 24 | off-heap (dim 300, 95MB) | Bigarray finalisation, off-heap footprint (input size = dim) |
| `owl_gc_default` | 14 | 11 | off-heap (dim 500, 230MB) | as small, bigger live set |
| `owl_gc_large` | 124 | 8 | off-heap (dim 1500, 1.9GB, 27ms max pause) | off-heap footprint + GC latency + custom-block pacer (M) |
| `owl_gc_huge` | 453 | 8 | off-heap (dim 2400, 4.77GB, 53ms max pause / 25ms p99.9) | off-heap footprint at scale + GC latency + pacer (M) |
| `zarith_pi` | 8 | 27 | off-heap (GMP custom blocks) | custom-block path, GMP stubs |
| `liq_video_frames_pool` | 4-20 | low | off-heap (Bigarray, refcounted pool) | custom_major_ratio pacer, refcounted-pool free lunch (#14533); frozen repro (720p×30000) |
| `liq_video_frames_pool_small` | 5.6 | 95 | off-heap pacer (1080p, 1104 majorGC) | custom_major_ratio pacing (input size = frame resolution) |
| `liq_video_frames_pool_default` | 22 | 94 | off-heap pacer (4K, 4413 majorGC) | as small, bigger per-frame off-heap |
| `liq_video_frames_pool_large` | 101 | 79 | off-heap pacer (8K, 16837 majorGC, ~5ms pauses) | major-GC pacing at scale (majorGC ∝ pixels²; RSS flat, read by collection counts) |
| `devkit_gzip` | 10 | 1 | compute-bound | codegen, zlib stubs |
| `devkit_stre` | 14 | 5.5 | minor + retention | string allocator, generational copy |
| `devkit_network` | 17 | 4.5 | minor (Int32) | int32 boxing, Hashtbl |
| `devkit_htmlstream` | 7 | 5 | minor + retention | Buffer allocator (input size = content-scale argv.1) |
| `devkit_htmlstream_small` | 7.1 | 5 | Buffer churn + peak heap (scale 1, 0.63GB peak) | input size = per-document content size (= frozen anchor) |
| `devkit_htmlstream_default` | 20 | 5 | churn + peak (scale 3, 1.86GB peak) | as small, bigger documents |
| `devkit_htmlstream_large` | 52 | 5 | churn + peak (scale 8, 4.57GB peak, max pause 141ms) | large-block sweeps; read by alloc_words+peak heap |
| `sedlex_tokenize` | 5 | 40 | minor-saturation | string allocation, PPX DFA |
| `sedlex_tokenize_small` | 5 | 43 | minor + retained token list (2M lines, 2.7GB) | minor-GC + promotion under a growing live heap (input size = # lines) |
| `sedlex_tokenize_default` | 17 | 49 | as small (6M lines, 8GB) | minor-GC/promotion throughput |
| `sedlex_tokenize_large` | 74 | 61 | minor + retained list (20M lines, 27GB, 153ms max pause) | minor-GC/promotion + pause latency under a large mostly-live heap (gc% RISES with size; steepest pauses in suite) |
| `ocamlformat_rocq` | 5 | 30 | minor + AST | Format module, AST allocation |
| `ocamlformat_rocq_small` | 5 | 33 | minor + AST (40k lines, 0.6GB) | Format, AST allocation, minor-GC throughput (input size = # lines) |
| `ocamlformat_rocq_default` | 13 | 32 | minor + AST (100k lines, 1.7GB) | as small, bigger live AST |
| `ocamlformat_rocq_large` | 100 | 29 | minor + AST (500k lines, 8.4GB, 90ms max pause) | minor-GC throughput + major-GC scan latency on a multi-GB live AST |
| `cpdf_merge` / `_blacktext` / `_squeeze` | 6-9 | 20-40 | minor + Bytes | Bytes mutation, codegen |
| `cpdf_scale` | 36 | 19 | minor (compute) | codegen of geometry transforms |
| `cpdf_squeeze_small` | 7.4 | 31 | live PDF object map (110M w, merge 8 copies) | input size = document working set (merge-N-copies + recompress) |
| `cpdf_squeeze_default` | 18 | 25 | live object map (225M w, 24 copies) | as small, bigger merged doc |
| `cpdf_squeeze_large` | 57 | 16 | live object map (405M w, 64 copies, RSS 3GB) | live-heap-driven; gc% falls as flate C recompress dominates |
| `alt_ergo_fill` | 14 | 40 | promotion-medium | SMT theory backends |
| `alt_ergo_yyll` | 19 | 6 | minor (compute) | native frontend, theory backends |
| `alt_ergo_unsat_smt2` | 15 | 7 | minor (compute) | Dolmen frontend, theory backends |
| `alt_ergo_chain_small` | 4.2 | 14 | live congruence structure (76M w, N=4000) | input size = single-solve problem size (chain VC a(i)=a(i-1)+1) |
| `alt_ergo_chain_default` | 14 | 18 | live congruence (244M w, N=7000) | as small, bigger single solve |
| `alt_ergo_chain_large` | 38 | 26 | live congruence (638M w, N=10500, RSS 4.9GB) | heap-scan-bound; gc% RISES, p99.9 pause 22ms |
| `menhir_sysver` | 7.8 | 32 | minor (sysver table, 0.72GB) | Hashtbl growth — input-size ladder rung **small** |
| `menhir_ocamly` | 13 | 20 | minor (ocaml canonical LR, 2.76GB) | Hashtbl scale, large arrays — ladder rung **default** |
| `menhir_sysver_canonical` | 87 | 36 | minor (sysver canonical LR `--table`, 4.0GB) | canonical state-table explosion — ladder rung **large** |
| `menhir_sql_parser` | 1.2 | 27 | minor (LALR + verbose, 0.31GB) | menhir internals — fast LALR extra, not a ladder rung |
| `ocamlc_self_compile` | 8.6 | 33 | minor-heavy + Marshal | Marshal (`.cmi`/`.cmo`), Hashtbl, Bigarray emit buffer, AST allocation |
| `ocamlc_compile_uucp` | 2 | 17 | major-active, collected (78MB) | data/constant tables → active major GC (opposite character to self_compile) |
| `ocamlc_compile_uucp_small` | 6 | 17 | major-GC-throughput (N=3, 87MB, 376 major) | compiler size ladder = uucp replicas; RSS flat, major GC scales |
| `ocamlc_compile_uucp_default` | 17 | 17 | major-GC-throughput (N=8, 90MB, 771 major) | as small, more replicas |
| `ocamlc_compile_uucp_large` | 58 | 18 | major-GC-throughput (N=25, 115MB, 1581 major, promo 1.36G w) | cheapest large in suite (RSS flat ~115MB); read by major-GC count |
| `jsoo` | 7.2 | 33 | minor + IR construction | jsoo bytecode parser, SSA dataflow, JS codegen |
| `jsoo_small` | 5 | 33 | minor + IR (5.6MB bytecode, 0.5GB) | whole-program IR alloc + minor-GC (input size = bytecode size) |
| `jsoo_default` | 16 | 31 | minor + IR (14MB, 1.7GB) | as small, bigger IR |
| `jsoo_large` | 50 | 33 | minor + IR (36MB, 7.8GB, 129ms max pause) | IR-alloc throughput + major-GC scan latency on a large SSA graph |
| `goblint` | 0.2-1 | high alloc | high allocation / churn (~1.3GB, 5.6KB input) | allocated_bytes (#13733), hash-consing, apron FFI |
| `goblint_gen_small` | 4.3 | 22 | alloc-churn (3.8G words, N=100) | input size = analysed-program size (synthetic Btor2C state machine) |
| `goblint_gen_default` | 16 | 27 | alloc-churn (14G words, N=165) | as small, bigger analysed program |
| `goblint_gen_large` | 47 | 34 | alloc-churn (40G words, N=240, RSS 186MB) | octagon O(N²); read by allocated_words not RSS |
| `frama_c_eva_sqlite_small` | 7 | 13 | weak/ephemeron hash-consing (457MB RSS, promo 0.6%) | ephemeron key-scan (#11733), CIL AST hash-cons, `Weak.Make` at scale |
| `frama_c_eva_sqlite_default` | 16 | 11 | as small, richer domains (641MB RSS, live 77M) | #11733 at higher precision |
| `frama_c_eva_sqlite_large` | 113 | 3 | max ephemeron churn (165k minor GC, 695MB RSS, 3.3s gc_time, 11.5ms tail pause) | #11733 ephemeron-clean throughput + GC latency (widening thrash, precision 3) |
| `infer_small` | ~9† | TBD | multicore shared-heap (72 roots, allocation-heavy abstract interpretation) | input size = #roots analysed; multi-domain shared-heap GC, minor+promotion, hashconsed type env |
| `infer_default` | ~16† | TBD | as small, more procedures (215 roots) | as small, larger analysis working set |
| `infer_large` | ~44† | TBD | as small, most procedures (542 roots, ~20x = full corpus) | shared-heap multicore GC at scale; read by wall + (pending) olly GC counts |

(`merlin_bench` and `lavyek_kv_*` omitted — disabled. frama-c input size = `-eva-precision` (2nd
wrapper arg); slevel is inert; no >5min huge rung reachable via EVA knobs — see
`docs/benchmarks/frama-c.md`. gc% FALLS with size (13→11→3%, mutator-bound at large) while
tail pause GROWS (3.1→8.9→11.5ms) — small/default GC-throughput-sensitive, large
GC-latency-sensitive. olly re-25|md-2, 5.5.0, 2026-07-24. †`infer` walls are WARM
`analyze --multicore` at `-j12` on a 32-core box, 5.5.0 (a cold first analysis is
~2-2.5x); gc% not yet olly-profiled; wall is machine-, jobs- and roots-relative, and
the shared per-runtime capture makes back-to-back rungs mildly order-dependent — see
its doc page.)

## Runtime-feature coverage matrix

Tags are assigned from **source-grounded** inspection of each benchmark's hot path
(read the driver `.ml`, `grep` the vendored tool for actual uses). We do not trust
upstream feature lists, only what is reachable from the workload we run. A tag whose
hot-path set is empty is a **coverage gap** (listed below). Re-audited 2026-09-21
against a `perf` profile and an `strace` of every small rung on 5.5.0; rows now cite
the measurement where there is one.

running-ng's `tags:` block is a **coarser selection layer** over this matrix, not a
mirror of it: a tag exists there only if it names runtime code someone actually edits
AND selects a set no other tag already gives you. So rows here like `hashtbl`,
`format`, `lazy` or `minor-gc` have no tag, and the 2026-09-21 trim also dropped the
`atomics`, `mutex_condition`, `pthread_affinity`, `foreign_threads`,
`subprocess_spawn`, `digests`, `lex_parse_engines`, `signals`, `memprof`, `kcas` and
`eio_fibers` selectors. Twelve runnable tags remain — `weak_refs`, `ephemerons`,
`effects`, `domains`, `marshal`, `compare_hash`, `c_side_allocation`,
`custom_blocks`, `bigarrays`, `ffi_bulk`, `off_heap_accounting`, `lwt` — and those
twelve are what the README table lists. Two more exist but select nothing and abort
loudly when named, which is how a gap stays discoverable: `io_uring` and
`ocaml_finalisers`. They are deliberately absent from the README, since that table is
a list of what you can run; this file is where they are documented.

| Tag | Runtime mechanism | hot-path benchmarks | cold |
|---|---|---|---|
| **minor-gc** | `caml_alloc_small` fast path, young-ptr bump | coqc_corelib_stress, menhir_*, alt_ergo_*, zarith_pi, sedlex_tokenize, devkit_{network,htmlstream,stre}, cpdf_*, ydump_repeat, liq_parse_typecheck, ocamlc_self_compile, jsoo, ocamlformat_rocq, goblint | — |
| **major-promotion** | minor→major copy, slice work | liq_parse_typecheck, ydump_repeat, test_decompress, eio_fiber_stream | most allocation-light benches |
| **custom-block finalisation** | `caml_alloc_custom_mem` + `finalize` cb; `caml_ba_finalize` | zarith_pi (`Z.t`, `caml_z.c:323`), owl_gc (`Bigarray.Array2`), liq_video_frames_pool (Y/U/V Bigarrays + `pool_stubs.c`), test_decompress (Bigstringaf), devkit_gzip (`z_stream`, `zlibstubs.c:61`), pplacer (GSL Vector/Matrix, which ARE Bigarrays), infer (sqlite3 db/stmt handles, `sqlite3_stubs.c:398,533,859`) | — |
| **explicit `Gc.finalise`** | `caml_final_register` from user OCaml | — (**verified gap**, 2026-09-21; running-ng tag `ocaml_finalisers`) | pplacer_testsuite only: `Gsl.Eigen.symmv` in `tests/pplacer/test_matrix.ml:10` registers one per workspace (`gsl-ocaml/src/eigen.ml:16`), a handful of calls. The `pplacer_like_*` ladder never reaches one — `diagd.ml` diagonalises without GSL. merlin_bench (`mreader_extend.ml:52`, not the query path) |
| **`Bigarray` allocation** | `caml_ba_alloc` (custom block + off-heap bytes) | owl_gc (dim×dim Float64 Array2; input size `OWL_MATRIX_DIM` scales it 100→2400, RSS 26MB→4.77GB), liq_video_frames_pool (1280×720 YUV420), test_decompress (Bigstringaf; `caml_ba_get_N` is 4.6% of cycles), pplacer_{testsuite,like_*} (`Gsl.Vector.vector` IS a float64 `Array1`, read by `linear_c.c:32` through `Caml_ba_data_val`), ocamlc_{self_compile,compile_uucp_*} (`emitcode.ml:52` emit buffer, 5.5.0) | — |
| **off-heap accounting / `custom_major_ratio` (M)** | `caml_alloc_custom_mem` → pacer | liq_video_frames_pool (the only bench whose wall+RSS Pareto front moves with M — the #14533 repro); owl_gc_{large,huge} (dim 1500/2400 → 18/46 MB Bigarrays, big enough to move the pacer — the input-size ladder now reaches this regime) | owl_gc (dim 100, ~80 KB blocks), zarith_pi, test_decompress (custom blocks too small to swing pacer policy) |
| **ephemeron GC machinery** (alloc + per-domain ephe list + `caml_ephe_clean` key scan) | `caml_ephe_create`, `caml_ephe_clean` | alt_ergo_* (all six, the chain rungs build terms too), frama_c_eva_* — via `Weak.Make`. NOT goblint: it has no `Weak.Make` anywhere in `analyzer/src`, its `GWeak` is a lattice, and vendored CIL contains no `Weak` at all (checked 2026-09-21). `Weak.*` is not a separate path: `runtime/weak.c` routes `caml_weak_*` through `caml_ephe_*` (a weak array is an ephemeron with no data field), so these drive ephemeron alloc + key-cleaning on the hot path (the path that regressed on OCaml 5, #11733). | — |
| **ephemeron *data-field*** (`Ephemeron.K1`-with-data) | `caml_ephe_set_data`/`get_data` + data branch of `caml_ephe_clean` | **coqc_{corelib_stress,tree_*}** — gap CLOSED 2026-09-21. `Compute` parses to `CbvVm` (`vernac/g_vernac.mlg:1145`), so every coq rung runs the bytecode VM, and `kernel/vmsymtable.ml:187,288` looks up each global through `CEphemeron`, which is `Ephemeron.K1.Make` with a value attached (`clib/cEphemeron.ml:67,93`). Partial: it runs at VM-compile time, once per global patched, not inside the reduction loop | merlin_bench `saved_parts.ml:3` (cold, disabled) |
| **`Weak.Make` / weak hashsets** | `caml_ephe_*` | frama_c_eva_sqlite{,_small,_default,_large} (CIL AST + EVA state via `State_builder.Hashconsing_tbl_weak`, largest weak workload; the `-eva-precision` ladder scales it 457→695MB RSS / 11k→182k minor GC), alt_ergo_* all six (`hconsing.ml:51`; `Expr`, `Xliteral`, `Hstring`, `Shostak` all construct through it) | — | <!-- goblint removed 2026-09-21: no Weak.Make in analyzer/src, none in vendored CIL -->
| **`Marshal.{to,from}_*`** | `caml_output_value*` / `caml_input_value*` | four distinct shapes: ocamlc_{self_compile,compile_uucp_*} writes (`.cmi` `cmi_format.ml:87`, `.cmo` `emitcode.ml:32`; uucp is 56 modules × the rung's replica count), jsoo_* reads (`parse_bytecode.ml:2962-2976` `input_value`s the whole DATA, SYMB and CRCS sections back into live values), coqc_* both ways (`lib/system.ml:254-256` for `.vo`, plus loading Corelib), infer_* round-trips every summary (`backend/Payloads.ml:102,111`, `Marshal.to_string ... [Closures]` into a SQLite blob) | liquidsoap-lang (`cache.ml`, the bench calls `Runtime.parse` directly), merlin `persistent_env` (cold), alt-ergo (`satml.ml:2206`, commented out) |
| **`Effect.perform` (OCaml 5)** | `caml_perform_*`, deep `try_with` | eio_fiber_stream and eio_conc_{small,default,large} (`suspend.ml:6`, `fiber.ml:11,170`; every blocking `Stream.add`/`take` performs one) | lavyek_kv_*d (disabled), merlin_bench cancellation (disabled) |
| **`Domain.spawn` / `join`** | `caml_domain_*` | infer (`--multicore`: single-process multi-domain shared-heap analysis, one domain per CPU of the inherited affinity mask — the suite's only non-disabled multi-domain workload, hence its only parallel-GC coverage. Source-audited 2026-09-21: `base/DomainPool.ml:134,98,238` `Domain.spawn`/`join`/`cpu_relax`, a hand-rolled pool over `Concurrent.Queue` (mutex + condvar), not Domainslib; `backend/ondemand.ml:56-90` reads `Domain.DLS` per analysed procedure) | lavyek_kv_{2,4,8}d, merlin_bench when re-enabled |
| **`Atomic.*`** | inlined CAS in native code, not a runtime symbol | — (**no measurable coverage**; the running-ng tag was dropped 2026-09-21) | eio_* (`waiters.ml:2,21,48`, one `bool Atomic.t` per suspension; `lib_eio_linux/sched.ml:67,100`) and infer_* (`base/Utils.ml:490-497` CAS loop, `base/Stats.ml` counters) do use Atomic, but uncontended and at a rate no profile sees: no `caml_atomic_*` or Atomic symbol appears anywhere in the 5.5.0 profiles. Contended atomics were lavyek's job (disabled). ocaml-re does Atomic only at regex compile time, so devkit_* see it only in init |
| **kcas / lock-free MCAS** | n/a (library) | — (**verified gap**: lavyek imports `kcas`/`kcas_data` but never calls them; `REMOVED.md:22`). The running-ng `kcas` selector was removed 2026-09-21, so this gap now lives only here | — |
| **`Sys.set_signal`** | `caml_install_signal_handler` | alt_ergo_unsat_smt2 only, and weakly: `--timelimit 15` arms an ITIMER_VIRTUAL per goal (`my_unix.ml:36-44` from `solving_loop.ml:149,169`; strace shows ~700 setitimer + ~700 rt_sigaction per run) and every invocation ends at 15.01 CPU-seconds on the SIGVTALRM, i.e. ONE delivery per run. The running-ng `signals` tag was dropped 2026-09-21: one delivery measures nothing about the poll path | alt_ergo_{fill,yyll,chain_*} (handlers installed at startup, no timer armed); coq SIGINT unused. No high-frequency signal delivery. |
| **`Lazy.force` (hot)** | `caml_call_lazy` | liq_parse_typecheck (`typechecking.ml:386`), jsoo (`inline.ml:195,429,714`), menhir_* (`invariant.ml`) | many cold init lazies |
| **`Format` (hot)** | `Format.{fprintf,pp_*}` | menhir_* (codegen + table dumps), ocamlformat_rocq (whole workload), liq_parse_typecheck (type printing), alt_ergo_*, zarith_pi (`Z.output`) | others use Format only on error paths |
| **`Hashtbl` at scale** | `caml_hash` | menhir_* (`LRijkstraClassic.ml:849`), ocamlc_self_compile (`btype.ml:46 TypeHash`), alt_ergo_*, cpdf_* (`camlpdf/pdf.ml:118`), irmin_mem_rw (`irmin_mem.ml:44`), liq_parse_typecheck (`repr.ml`), pplacer (`ptree.ml:4`), devkit_*, goblint | others touch Hashtbl only trivially |
| **Lwt promises** | `Lwt.bind` continuations | irmin_mem_rw{,_small,_default,_large} (every store op) — but coverage of the pattern only: the benchmark is in-memory so no Lwt engine tick runs, and no Lwt symbol reaches the profile's top 20. What dominates is digestif's BLAKE2B C stubs at 38.1% of cycles (every content-addressed write hashes its value) | — |
| **Eio fibers (effects layer)** | `Eio.Fiber.*`, `Eio.Stream`, `Eio.Switch` | eio_fiber_stream | lavyek_kv_*d (disabled) |
| **io_uring (real syscalls)** | `Uring.t` via `eio_linux` | — (**gap**: only lavyek_kv_*d, disabled) | eio_* DO create a ring: `Eio_main.run` picks the Linux backend first (`lib_main/eio_main.ml:9-13`), and strace of eio_conc_small shows 1 io_uring_setup + 2 io_uring_register + 1 eventfd2 — but exactly **2** io_uring_enter for a whole run, so the ring is set up and then idle |
| **CPU pinning** | `pthread_setaffinity_np` via `ocaml-processor` | infer_* — gap closed: `scripts/vendor-infer.sh:121-160` patches `DomainPool.child` to `Processor.Affinity.set_ids` one CPU per worker (87.9s unpinned vs 26.3s pinned on an isolcpus host). Not a runtime feature, so no tag | lavyek_kv_*d (`lavyek_bench.ml:59`) when re-enabled |
| **OpenBLAS / GMP / GSL / sqlite3 / zlib C stubs in inner loop** | bulk FFI measured share of cycles, 2026-09-21: owl_gc (OpenBLAS, 97.8% in libopenblasp — which also spawns ~30 OS threads the runtime knows nothing about, so per-process perf counters under-count it), zarith_pi (GMP, 66.7% in libgmp), devkit_gzip (zlib, 66.9% in libz), pplacer_* (61.6% in its OWN `linear_c.c` kernel over Bigarrays, NOT BLAS and NOT sqlite3 — the testsuite loads libsqlite3 but never opens a database), irmin_mem_rw_* (digestif BLAKE2B C stubs, 38.1%), cpdf_* (miniz `tdefl_compress`, linked into the exe), alt_ergo_unsat_smt2 (GMP via Q/Z, ~12%), infer_* (sqlite3) | test_decompress is pure-OCaml zlib (FFI-free counterpart); alt_ergo_chain_*, frama_c_eva_*, goblint_* all key integers on Zarith but stay on its OCaml small-int fast path (`z.ml:39-49`), so no GMP call. goblint's apron/GMP fires only for the legacy `goblint` program, where autotune enables the octagon domain — the `goblint_gen_*` ladder never does (checked by running it) |
| **polymorphic compare / hash** | `compare_val`, `caml_compare`, `caml_string_compare`, `caml_hash` (`runtime/compare.c`, `runtime/hash.c`) | cpdf_* (compare_val 17.2% + caml_hash 3.8% + caml_compare 1.9%), frama_c_eva_* (caml_string_compare 7.8% + caml_hash 2.0%), menhir_* (caml_hash 5.9% + compare_val 2.9%), ocamlformat_rocq_* (compare_val 3.7% + caml_hash 4.4% + caml_hash_mix_string 2.9%), goblint_* (compare_val 2.5-4.8% + caml_hash 1.4%), devkit_network (3.6% + 3.2%), ocamlc_* (caml_string_compare 2.5% + caml_hash 2.3%) — running-ng tag `compare_hash` | reached through Stdlib Map/Set/Hashtbl on non-specialised keys, so most analysers pay some |
| **C-side allocation into the OCaml heap** | `Alloc_small` / `caml_alloc_shr` / `caml_modify` called from a foreign mutator, with its own GC-entry and poll points | coqc_* — rocq's bytecode VM is a C interpreter building OCaml blocks (`kernel/byterun/rocq_interp.c:36,123` its own Alloc_small with an Enter_gc path, `:811,1215` caml_alloc_shr, `:916,1095` caml_modify, `:616` Caml_check_gc_interrupt in the loop); coqc_tree_small spends 16.8% in caml_shared_try_alloc. cpdf_* in miniature (`camlpdf/flatestubs.c:58,68,113`) — running-ng tag `c_side_allocation` | distinct from bulk FFI, where the C side only touches memory OCaml already owns |
| **`Gc.compact` / `Gc.full_major` forced** | `caml_compact_heap`, `caml_finish_major_cycle` | — (**verified gap**) | eio `bench/` calls `Gc.full_major` outside the hot path; infer has a compaction path (`base/DomainPool.ml:205-225`) but its multicore threshold defaults to available RAM, so it never fires on our rungs |
| **`Gc.alarm` callbacks** | alarm register | — (**verified gap**) | — |

### Per-benchmark tag summary (reverse index, hot-path tags only)

| Benchmark | Hot-path tags |
|---|---|
| `coqc_corelib_stress{,_tree_small,_tree_default,_tree_large}` | ephemeron data-field (`CEphemeron` on the VM's global-slot path), C-side allocation (the VM's own `Alloc_small`/`caml_alloc_shr`/`caml_modify`; `caml_shared_try_alloc` 16.8%), marshal (`.vo` both ways) + `Digest.string`, minor-gc, constructor-alloc. NB `Compute` is `vm_compute`, so these run the bytecode VM, not just kernel reduction; `coqc_bin.exe` execve's itself into `rocqworker` and the wrapper shells out to ocamlfind twice; input size = numeral/make_tree depth → minor-GC-saturation ladder (RSS 0.57→1.89GB, gc% 90→97% = highest in suite) |
| `eio_fiber_stream` | effects, eio-fibers, major-promotion; `Eio.Stream` takes a Mutex per op (`caml_ml_mutex_lock` ~2.3% + pthread_mutex ~7% on eio_conc), and Eio_main creates an io_uring that then stays idle |
| `eio_conc_{small,default,large}` | input size = concurrency degree (eio_conc_bench.ml: N=3000/9000/21000 independent producer/consumer fiber pairs, each on own bounded stream; per-fiber work fixed 20000). Live-set ladder: retained fibers+buffers, top_heap 84->619M w, RSS 0.69->4.96GB, promo ~0.85 flat -> gc% ~62% (heavy, 2nd to liqvf), max pause 6.5->76ms. Effects-scheduler counterpart to goblint(churn)/pplacer(off-heap). Read by RSS/top_heap. Frozen eio_fiber_stream (throughput) unchanged |
| `merlin_bench` *(disabled)* | domains, effects, atomics, hashtbl, format; cold: ephemerons, Gc.finalise |
| `lavyek_kv_1d` *(disabled)* | atomics, effects, eio-fibers, io-uring, pthread-affinity, hashtbl |
| `lavyek_kv_{2,4,8}d` *(disabled)* | domains, atomics, effects, eio-fibers, io-uring, pthread-affinity, hashtbl |
| `liq_parse_typecheck{,_small,_default,_large}` | hashtbl, lazy, format, major-promotion, minor-gc; input size = script size (argv.2 = generated unit count, in-process) → promotion-heavy AST+type-env ladder (RSS 0.26→0.72GB, ~60% gc%, super-quadratic wall) |
| `ydump_repeat{,_small,_default,_large}` | minor-gc, major-promotion, recursive-variants, `caml_lex_engine` 12.3% (the suite's only hot ocamllex); input size = doc size (argv.2 = generated record count, in-process) → promotion-heavy footprint ladder (RSS 3.25→20GB), 424ms max pause (largest in suite) |
| `test_decompress{,_small,_default,_large}` | bigarray, custom-block-finalisation (Bigstringaf), major-promotion; input size = payload size (argv.2) → compute+Bigstring footprint ladder (RSS 0.5→5.7GB), gc% ~0.8% (compute-bound control) |
| `pplacer_testsuite` | custom-block-finalisation + bigarray (GSL Vector/Matrix are Bigarrays), ffi-stubs (its own `linear_c.c`), hashtbl, minor-gc, `caml_parse_engine` 0.7%; the suite's only `Gc.finalise` (via `Gsl.Eigen.symmv` in `tests/pplacer/test_matrix.ml`, a handful of calls). NOT sqlite3: libsqlite3 loads, no database is ever opened |
| `pplacer_like_{small,default,large}` | input size = likelihood n_sites (like_bench.ml: Felsenstein pruning + 40-pt ML pendant scan over GSL Glv). bigarray + ffi-stubs (61.6% of cycles in `gemmish_c`). Off-heap footprint: top_heap ~2-8MB while RSS 0.22→2.18GB, allocated_words 2.1→22.4G, minor 8k→86k, major 147→646. gc%~0.6 flat (compute-bound, promo~0) — the suite's compute-bound/off-heap corner, read by RSS/alloc_words like owl |
| `owl_gc{,_small,_default,_large,_huge}` | bigarray, custom-block-finalisation (Array2, finalised by the runtime's `caml_ba_finalize` — owl calls `Gc.finalise` exactly once in its whole tree, in an NLP module no bench reaches; the free order is what moved on #14571), ffi-stubs (OpenBLAS, 97.8% of cycles, on ~30 OS threads it spawns itself so perf sidecars under-count), minor-gc; input size = matrix dim (`OWL_MATRIX_DIM`, 2nd wrapper arg) → off-heap footprint ladder (RSS 95MB→4.77GB); large/huge also hit off-heap-accounting pacer |
| `liq_video_frames_pool{,_small,_default,_large}` | bigarray, custom-block-finalisation, off-heap accounting (M-sweep); input size = frame resolution (argv.2/3) → major-GC-pacing ladder (majorGC 1104→16837 @ 1080p→8K, gc% ~80-95%, RSS flat) |
| `zarith_pi{,_small,_default,_large,_huge}` | custom-block-finalisation (`Z.t`), ffi-stubs (GMP, 66.7% of cycles in libgmp), minor-gc, format(cold) |
| `devkit_gzip` | custom-block-finalisation (z_stream), ffi-stubs (zlib), hashtbl, buffer |
| `devkit_stre` | hashtbl, minor-gc, buffer, string-allocator |
| `devkit_network` | hashtbl, int32-boxing, minor-gc |
| `devkit_htmlstream` | hashtbl, buffer, minor-gc |
| `devkit_htmlstream_{small,default,large}` | input size = per-document content-size scale (argv.1=1/3/8; multiplies HTML-element counts + retained-structure sizes, outer repetition fixed, super-linear pieces left fixed). Churn+peak-RSS ladder: allocated_words 1.65→12.3G, peak heap 0.63→4.57GB, RSS 0.37→2.57GB, minor 3.8k→28k. gc% low ~5% flat (parse-bound), but max GC pause 22→141ms (large-block sweeps). Read by alloc_words + peak heap |
| `sedlex_tokenize{,_small,_default,_large}` | bytes, ppx-match, string-allocator, minor-gc; input size = input size (argv.1 # lines) → retained-token-list footprint ladder (RSS 2.7→27GB), gc% RISES 43→61%, 153ms max pause (steepest in suite) |
| `ocamlformat_rocq{,_small,_default,_large}` | format, buffer, minor-gc; input size = source size (# lines, generated N× workload.ml) → live-AST footprint ladder (RSS 0.6→8.4GB), constant ~30% gc% + growing major-GC scan pauses (90ms @ large) |
| `cpdf_{merge,blacktext,scale,squeeze}` | polymorphic compare/hash (compare_val 17.2%, the suite's heaviest), hashtbl (object map), bytes mutation, minor-gc, C-side allocation (`flatestubs.c`); camlpdf C stubs (flate/zlib, AES, SHA-2) hit when decoding/re-compressing streams (squeeze), otherwise pure OCaml |
| `cpdf_squeeze_{small,default,large}` | input size = document working set (merge N=8/24/64 copies + recompress). Live PDF object map grows ~linearly with N (top_heap 110→405M w, RSS 0.88→3.0GB, majorGC 38→56); gc% FALLS 31→16% as flate C recompression dominates. Live-heap ladder, not a GC-pacing one |
| `alt_ergo_fill, alt_ergo_yyll` | weak-refs (Weak.Make hash-consing), hashtbl, format |
| `alt_ergo_chain_{small,default,large}` | input size = single-solve problem size (generated chain VC a(0)=0, a(i)=a(i-1)+1, prove a(N)=N; N=4000/7000/10500). One large mostly-live congruence structure per solve: top_heap 76→638M w, RSS 0.6→4.9GB, minor 3.7k→25k (major only 16→24, promo ~0.1). gc% RISES 14→26%, pauses grow (p99.9 3→22ms) — heap-scan-bound. Distinct from fill_x100's fixed-input repetition |
| `alt_ergo_unsat_smt2` | weak-refs, hashtbl, format, ffi-stubs (GMP via Q/Z, ~12%: `ml_z_gcd` 5.0%, `Z.mul` 2.7%), signals (the `--timelimit 15` SIGVTALRM fires every run — it never proves its goal, so it measures 15s of solver work, not a fixed amount of it) |
| `frama_c_eva_{t,sqlite,sqlite_small,sqlite_default,sqlite_large}` | weak-refs / ephemeron-backed hash-consing (`State_builder.Hashconsing_tbl` is the weak variant unless `-deterministic`; `Stdlib.Weak.find_aux` 1.8% of cycles), polymorphic compare/hash (caml_string_compare 7.8%), forks the C preprocessor inside the measured region, hashtbl, recursive-variants (CIL AST), minor-gc, max-rss (sqlite, #11733). input-size ladder = `-eva-precision` (2nd wrapper arg) on sqlite; slevel inert; t is a fixed fast standalone |
| `goblint` | high allocation / minor-gc churn (~1.3GB for a 5.6KB input), polymorphic compare/hash, apron relational domains (C/GMP FFI — autotune enables the octagon domain for THIS program only, not for the gen_* ladder), forks the C preprocessor inside the measured region, recursive-variants (CIL AST), allocated-bytes (#13733) |
| `goblint_gen_{small,default,large}` | input size = analysed-program size (synthetic Btor2C bit-vector state machine, N=100/165/240 state vars; goblint.build.sh generates the .c). Pure allocation-churn ladder (#13733 signature): allocated_words 3.8→39.5G (10×), minor GC 15k→151k, gc% 22→34%; live set grows too (top_heap 5.9→19.5M, major 41→97) but RSS modest 77→186MB. octagon O(N²) in the generator, but autotune does NOT enable the apron octagon domain here (verified by running it). Polymorphic compare/hash (compare_val 2.5%) and a forked cpp. Read by allocated_words. On-heap counterpoint to pplacer's off-heap footprint |
| `menhir_{sysver,ocamly,sysver_canonical,sql_parser}` | hashtbl, format, lazy, minor-gc; input-size ladder (automaton scale) = small sysver--table / default ocaml--canonical / large sysver--canonical--table, monotone by wall 7.8→13→87s AND RSS 0.72→2.76→4.0GB. sql_parser (LALR 1.2s) = fast extra, not a rung. Single-run (menhir has no loopable main) |
| `ocamlc_self_compile` | hashtbl, marshal (`.cmi`+`.cmo` writeout), bigarray (emit buffer), polymorphic compare/hash (caml_string_compare 2.5% + caml_hash 2.3%), `caml_lex_engine` 2.0%, `Digest.BLAKE128` per cmi (MD5 pre-5.5), minor-gc |
| `ocamlc_compile_uucp{,_small,_default,_large}` | Compiler tool's size ladder = compiling N replicas of uucp (prefix-renamed Uucp→UucpK). uucp's COLLECTED heap → RSS flat ~87-115MB while major-GC scales (N=3/8/25 → major 376/771/1581, promo 0.14/0.40/1.36G w, 6/17/58s). gc% ~17% flat, pauses ~2-4ms. Major-GC-throughput ladder (vs self_compile's monotonic-heap memory-bound). build.sh stages a renamed ocamlc (`..._bin`) for olly attach (like self_compile) |
| `jsoo{,_small,_default,_large}` | hashtbl, lazy, marshal — NOT cold: `read_data`/`read_symb`/`read_crcs` (`parse_bytecode.ml:2962-2976`) `input_value` whole bytecode sections back into live values, scaling with the rung; input size = input bytecode size (rung arg → generated per-runtime .byte from real JSOO sources × R replicas) → whole-program-IR footprint ladder (RSS 0.5→7.8GB), constant ~33% gc% + 129ms max pause @ large |
| `infer_{small,default,large}` | multi-domain shared-heap GC (`--multicore`, `INFER_JOBS` domains), minor-gc + major-promotion (allocation-heavy abstract interpretation), hashtbl (hashconsed type env), marshal (`Marshal.to_string ... [Closures]` per summary into a SQLite blob, `backend/Payloads.ml:102,111`), custom blocks (sqlite3 handles), Domain.DLS per procedure, mutex+condvar queues, CPU pinning we patch in; input-size ladder = roots-subset size (72/215/542 classes → warm ~9/16/44s at -j12), flat capture footprint. Source-audited 2026-09-21 against the pinned tree (`ngorogiannis/infer@inferbench-v1.1`) |

## Coverage gaps — verified

A regression in any of these areas would **not** be caught by the current suite.
Each was checked by `grep -rn` against the actual vendored source.

- **Multi-domain parallelism** — covered by infer alone, and that is fragile. `infer
  analyze --multicore` drives one domain per CPU over a shared heap (source-audited
  2026-09-21: `DomainPool.ml` spawn/join/cpu_relax, `Concurrent.Queue` mutex+condvar,
  `Domain.DLS` per procedure — a hand-rolled pool, NOT Domainslib), which makes it the
  suite's only exercise of the parallel GC. But infer is network-vendored by
  `scripts/vendor-infer.sh` and needs a Java corpus, so if it fails to build the suite
  has zero multi-domain coverage. A small always-available multi-domain rung would be
  cheap insurance. Per-domain CPU pinning is no longer a gap (we patch it into infer's
  DomainPool), though it is a harness property, not a runtime feature.
- **Real io_uring syscall traffic** — still a gap, now measured rather than assumed.
  `Eio_main.run` does pick the eio_linux backend, so eio_* create a ring, but
  `strace` of eio_conc_small shows exactly 2 `io_uring_enter` for the whole run: the
  workload is in-memory, so the ring is set up and then idle. An eio rung doing real
  file or socket I/O would close it.
- **Contended atomics** — uncovered. eio_* and infer_* both use `Atomic`, but
  uncontended and at a rate that reaches no profile (native atomics are inlined, and no
  `caml_atomic_*` symbol appears anywhere in the 5.5.0 profiles). This matters because
  the live runtime work here — memory-model fences, arm64 LSE codegen,
  `Atomic.make_contended` padding — only shows up under contention. Was lavyek's job.
- **Ephemeron data-field semantics** — CLOSED 2026-09-21 by coq, partially. `Compute`
  is `vm_compute`, so every coq rung runs the bytecode VM, whose symbol table looks up
  each global through `CEphemeron` = `Ephemeron.K1.Make` with a value attached. It runs
  at VM-compile time, once per global patched, not in the reduction loop, so a workload
  that churns ephemeron tables (re-typechecking, incremental elaboration) is still worth
  having. Separately, `runtime/weak.c` routes `caml_weak_*` through `caml_ephe_*`, so
  the key-scan machinery is covered by the `Weak.Make` workloads: `frama_c_eva_*` and
  `alt_ergo_*` — NOT goblint, which has no `Weak.Make` at all (nor does vendored CIL).
- **`Gc.finalise` proper** — near-gap. Only `pplacer_testsuite` registers any, via
  `Gsl.Eigen.symmv`, a handful of calls; the `pplacer_like_*` ladder registers none.
  Custom-block finalisation (the `finalize` op, e.g. `caml_ba_finalize`) is well covered
  and is a different path — see the matrix row.
- **kcas / lock-free MCAS** — verified gap. Even when lavyek was enabled it didn't call
  kcas (`REMOVED.md:22`). A small standalone benchmark wrapping `kcas` would close it.
- **Domainslib work-stealing pools** — uncovered (eio uses fibers; infer hand-rolls its
  pool; lavyek dispatched via a manual `Atomic.fetch_and_add` counter).
- **`Gc.compact` / `Gc.full_major` in a hot loop** — no benchmark forces a full GC.
- **`Gc.alarm` / `Gc.create_alarm`** — no benchmark registers one.
- **High-frequency signal delivery in tight loops** — alt-ergo installs handlers ~700
  times per run and arms an itimer per goal, but exactly one signal is delivered, at
  the end of `alt_ergo_unsat_smt2`. Nothing measures the poll-point path, which is the
  part of this that runtime work actually touches.
- **Pure-OCaml hot inner-loop float (flambda)** — owl_gc defers to OpenBLAS, so flambda
  has nothing to optimise in the inner loop. A pure-OCaml numerical kernel would catch it.
- **`Bigarray` slicing / reshape patterns** — owl_gc doesn't slice; liq_video_frames_pool
  fills planes without slicing.
- **Polling-points / safe-point density** — nothing stresses cooperative cancellation.
- **Direct user `Effect` handlers (outside Eio)** — every effect-perform goes through Eio.

If a runtime change touches one of these areas, flag the gap explicitly when proposing it.

## Vendored source patches

Applied automatically by `scripts/setup-monorepo.sh`.

| # | Target | What | Why |
|---|--------|------|-----|
| 1 | `duniverse/alt-ergo/.../theories.ml` | Fix ppx_blob paths | ppx_blob resolves from workspace root |
| 2 | `duniverse/alt-ergo/.../text/dune` | Rewrite dune file | Remove public_name/package (vendored exec) |
| 3 | `duniverse/dune_/dune-project` | `3.22` → `3.21`, rm test/ | dune 3.22 features not in installed dune |
| 4 | `duniverse/ppxlib/` | Replace with a pinned commit (`sources.yml`) | Adds Ast_506 for OCaml 5.6 trunk |
| 5 | `duniverse/lwt/` | Replace with a pinned commit (`sources.yml`) | Fixes socketaddr.h for OCaml 5.6 |
| 6 | `duniverse/devkit/lwt_engines.ml` | Add `engine_id` type + method | lwt 6.1.1 added virtual `id` method |
| 7 | `vendor/libevent/libevent.ml` | Add `~persist`, `~signal` labels | OCaml 5.x strict label matching |
| 8 | `duniverse/js_of_ocaml/.../dune` | Remove `public_name`/`package` from the executable stanza | Vendored executable. Match on **content, not line number**: upstream reordered these fields (`public_name` moved from line 2 to line 3) and the old line-anchored `sed` silently became a no-op that still logged success |
| 9 | `duniverse/ocamlformat/.../dune` | Remove public_name | Vendored executable |
| 10 | `duniverse/owl/.../exponpow.c` | Fix `std_gaussian_rvs` calls | Upstream C bug: function takes no args |
| 11 | `duniverse/batteries-included/.../batGc.mli` | Add `live_stacks_words` field | OCaml 5.6 added field to `Gc.stat` |
| 12 | `vendor/pplacer/mcl/caml/caml_mcl.c` | Add `#include <stdint.h>` | OCaml 5.6 trunk headers need it |
| 13 | `vendor/pplacer/tests/tests.ml` | Add `PPLACER_TEST_LOOP` env-var loop | Run the suite N times in one process (see Iteration counts) |
| 14 | `duniverse/analyzer/.../runtime/include/goblint.h` | `__goblint_assume_join` arg type | GCC 14+/C23 conflicting-types vs the `.c` definition |
| 15 | `duniverse/cpu/` | Run `autoconf; autoheader; ./configure` **with `$TOOLS_BIN` on `PATH`** | Generates `src/config.h` its C stub needs (opam runs this; dune doesn't). `./configure` probes for `ocamlc` and aborts with "You must install the OCaml compiler" without one, and this patch section runs *before* step [8] puts `$TOOLS_BIN` on `PATH` — so it must set it itself. Failure is fatal: it used to be a swallowed warning, and the only symptom was goblint failing much later with `cpu_stubs.c:1:10: fatal error: config.h: No such file or directory` |
| 16 | `duniverse/json-data-encoding/.../json_repr.{ml,mli}` | Add `` `Tuple ``/`` `Variant `` to `Json_repr.Yojson` | dune-universe fork narrows the type; goblint treats it as `Yojson.Safe.t` both ways |
| 17 | `duniverse/bare-ocaml/src/dune` | Install `Bare_encoding.ml`/`.mli` | catapult copies them via `%{lib:bare_encoding:…}` (needs source installed) |
| 18 | `duniverse/analyzer/.../control.ml` | Annotate `(module CFG : CfgBidirSkip)` | OCaml ≥ 5.5 can't infer the packaged-module signature otherwise |
| 19 | `duniverse/rocq/dune-project` + `dune` | Drop `(using coq 0.8)` and the `dev`-profile `(coq (flags ...))` | dune 3.24 deleted the `coq` extension. It's a *parse* error, so it broke **every** build in the workspace, not just rocq's. Both declarations are dead here (rocq generates its theory rules via `tools/dune_rule_gen`; the only stanzas needing the extension are in `dune.disabled` files), so they're removed rather than ported to `(using rocq ...)` |
| 20 | `duniverse/rocq/toplevel/dune` | Collapse the `(select memtrace_init.ml …)` to its `(-> memtrace_init.default.ml)` default clause | rocq-runtime has an *optional* memtrace integration (`(select)` + `depopts: memtrace`). dune auto-enables it the moment `memtrace` is present anywhere in the workspace — which it is once a benchmark vendors memtrace — so `rocq-runtime.toplevel` gains `requires memtrace` in its generated META. The rocq bootstrap's `gen_rules.exe` resolves that library through findlib on `$OCAMLPATH`, where the vendored memtrace is never installed, and dies with `findlib error: memtrace not found … required by rocq-runtime.toplevel`. Forcing the default (memtrace-free) clause keeps rocq's toplevel from ever linking/requiring memtrace, independent of any benchmark vendoring it |
| 21 | `duniverse/sedlex` unicode download rule | Add `--fail` to the `curl` invocations | A failed download otherwise wrote an HTML error page as if it were Unicode data, and the smoke build failed non-deterministically much later |
| 22 | `duniverse/sedlex` `unicode.ml` rule | Remove the rule that regenerates `unicode.ml` from a live download | The vendored tree already ships a generated `unicode.ml`; regenerating it made the build depend on the network. Refuses to patch (keeping the rule) if the shipped `unicode.ml` is missing or unrecognised |
| 23 | `vendor/camlpdf/pdftree.ml` | Drop the duplicate name/number tree key warning | `cpdf_squeeze` merges N copies of one PDF, so every key collides; camlpdf logged ~13M flushed stderr lines per `_large` invocation (~830 MB of log, and stderr I/O inside the measured region). Dedup behaviour unchanged; other `Pdfe` diagnostics still print |
| 24 | `duniverse/analyzer/src/maingoblint.ml` | Guard the `-m32`/`-m64` cpp flag on x86 hosts only | goblint's sv-comp preprocessing maps `exp.architecture` 64bit/32bit to `cpp -m64`/`-m32`, which are x86-only; on aarch64 `cpp` rejects `-m64` ("unrecognized command-line option") and every goblint analysis dies in the preprocessor. Guarded on the host actually being x86 (via `uname -m`) — x86 behaviour is unchanged, and the word size is already native on aarch64, so omitting the flag is correct |
| 25 | `duniverse/extunix/discover/discover.ml` | Add a fifth `gettid` probe alternative: `pthread_getthreadid_np()` from `<pthread_np.h>` | FreeBSD. devkit calls `U.gettid ()` where `U = ExtUnix.Specific`, and `ExtUnix.Specific` exposes only what the platform has. extunix implements `gettid` four ways (Win32, macOS `pthread_threadid_np`, older macOS `SYS_thread_selfid`, Linux `SYS_gettid`) and FreeBSD matches none of them purely on spelling, so devkit fails to compile with `Unbound value U.gettid` and takes `benchmarks/ahrefs-devkit` with it. The probe is ordered, so Linux still wins on `SYS_gettid` and nothing changes there |
| 26 | `duniverse/owl/src/owl/config/configure.ml` | Add FreeBSD OpenMP flags (`-fopenmp` / `-lomp`), and add `-lomp` whenever the assembled cflags ask for OpenMP and the libs carry no runtime | FreeBSD. owl's stubs compile but fail to link with `undefined symbol: __kmpc_fork_call`. Two holes: `get_openmp_config` has no FreeBSD arm (everything unmatched gets no flags), and FreeBSD's openblas is built with OpenMP threading, so `pkg-config --cflags openblas` returns `-fopenmp` while `--libs` returns no runtime. The second diagnosis is inferred from the link error and the flag assembly, not observed on hardware: if owl still fails, dump the assembled cflags/libs rather than guessing |
| 27 | `vendor/pplacer` `gsl-ocaml` `src/config/discover.ml` | Probe for the gsl headers instead of falling back to a hardcoded `/usr/include` | FreeBSD. pplacer dies in a dune rule with `Sys_error("/usr/include/gsl/gsl_cdf.h: No such file or directory")`; gsl is under `LOCALBASE`. *Why* the default is reached is NOT established: `pkg-config --cflags gsl` does emit `-I/usr/local/include` on FreeBSD, so the earlier "pkgconf strips system include paths" explanation is false. Candidates are `C.Pkg_config.get` returning `None` (pkg-config not on PATH in dune's build env) or the gsl query failing because its `.pc` lives in `/usr/local/libdata/pkgconfig`. Both are guesses |
| 28 | `duniverse/analyzer/src/util/parallel/dune` | Drop both `(domainslib -> …)` alternatives from the `select`, leaving the no-domainslib defaults | Platform-independent, and a **measurement** bug, not just a build failure. `domain-local-await` is a hard dep of goblint so opam-monorepo vendors it; `domainslib` is a depopt so it is not. When the runtime switch happens to carry domainslib the select resolves to the domainslib branch, which drags in the *switch's* `domain-local-await` alongside the vendored one, and dune refuses the ambiguity. Whether the switch carries domainslib is not a property of this repo: running-ng's `install_deps_*.sh` install it for the micro suite's `multicore/` benchmarks, so a machine that ran micro before macro built a different goblint. Pinned to the no-domainslib branch, which is what every goblint figure we have was produced with |
| 29 | `duniverse/cil/bin/realGccConfigure.ml` | Also try unhyphenated versioned GCC names (`gcc14`, `gcc13`, …), after plain `gcc` | FreeBSD. goblint dies at configure time with `couldn't find real gcc`: CIL only tries `gcc` and hyphenated `gcc-7`..`gcc-16`, and FreeBSD's pkg installs `gcc14`. It has to be a real GCC (CIL's `is_bad_gcc_version` correctly rejects anything whose `--version` mentions clang, and `cc` on FreeBSD is clang). Plain `gcc` stays first, so Linux picks what it picked before |
| 30 | `duniverse/analyzer/src/util/preprocessor.ml` | Also search the unhyphenated `cpp` prefix (`cpp14`, …) when the hyphenated one yields nothing | FreeBSD, and the same problem as 29 one layer up. `/usr/bin/cpp` on FreeBSD is clang, which goblint correctly rejects, and the `compgen -c cpp-` fallback only finds Debian-style `cpp-14`. Symptom is at **run** time, long after a clean build: `No good preprocessor (cpp) found`. `"cpp-"` is kept first and every candidate still goes through `is_good`, so Linux is unchanged. Requires a real GCC to be installed (see README's FreeBSD prerequisites) |
| 31 | `duniverse/Zarith/dune` | `grep "version" META \| head -1` becomes `grep -m1 "version" META` | dune runs every `(bash ...)` action as `bash -e -u -o pipefail -c`. zarith's META has **two** lines matching `version` (its own 1.14 and zarith_top's 1.13), so `head -1` exits while grep still has the second to write; grep takes SIGPIPE and `pipefail` promotes its **141** to the pipeline, failing the rule and with it the whole rocq bootstrap (step [8/9]). Whether it fires is a buffering race: GNU grep block-buffers to a pipe so both lines usually land in one `write()` that beats `head`'s exit, while FreeBSD's grep is line-buffered and loses the race far more often. It is latent on every platform, not a FreeBSD bug. `-m1` stops after the first match, so there is no second write and no pipe; output is byte-identical and `-m` is in both GNU and BSD grep |

## Known limitations

- **Rocq symlink**: setup creates a symlink at
  `<parent_of_monorepo>/install/default/lib/rocq-runtime` pointing at `_rocq_prefix/`,
  because dune's generated `.vo` rules use relative paths that resolve outside the
  monorepo. `make clean-all` removes it.
- **melange**: parked. Needs the `(using melange 0.1)` dune extension; can't benchmark
  standalone.
- **Frama-C / dune-site**: EVA is linked statically (`-linkall`) and run with
  `-no-autoload-plugins`, so dune-site plugin discovery is never used (the `.cmxs` path
  doesn't work for a relocated, uninstalled build). Its resource sites are empty in an
  uninstalled build, so `frama-c.build.sh` sets `DUNE_DIR_LOCATIONS` at `vendor/frama-c`.
  WP is excluded (its `why3` dep caps OCaml < 5.5); EVA needs neither.
- **goblint / apron**: apron is non-dune (configure/make + camlidl), so it can't join the
  unified dune build. `scripts/vendor-apron.sh` builds the camlidl/mlgmpidl/apron chain
  per-runtime from pinned source into a self-contained prefix (opam-free: active compiler
  + gcc + ocamlfind + make), and `goblint.build.sh` exposes it via `OCAMLPATH`. Runtime
  stubs are found via `pre.custom_includes` since dune-site sites aren't populated in an
  uninstalled build. On trunk goblint builds from `fb4f451` onward (the late-May
  `cfb30145` snapshot hit a since-fixed `Ctype.Unify` compiler bug). The apron chain needs
  gmp+mpfr **dev** headers; on a no-sudo box that lacks `libmpfr-dev` (only the runtime
  `libmpfr.so.N` present, e.g. this aarch64 box) `vendor-apron.sh` builds MPFR from pinned
  source (`sources.yml` `mpfr`) into `vendor/.mpfr-prefix` and feeds `mlgmpidl` (via
  `CPPFLAGS`) and `apron` (via `MPFR_PREFIX`, which apron wants instead of `-I`) — skipped
  when the system already provides `mpfr.h` (Linux x86 apt, FreeBSD pkg, macOS brew).
- **OxCaml**: only menhir, test_decompress, and zarith_pi work; others fail on
  locality-type annotation errors in vendored packages.
- **Trunk (5.6) support**: depends on ppxlib and lwt git main (patches 4+5). When ppxlib
  releases a 5.6-compatible version, these can be dropped and the lock file updated.
- **pplacer**: vendored manually (not in opam); needs `libgsl-dev` and `libsqlite3-dev`.
- **frama-c**: vendored manually (`scripts/vendor-frama-c.sh`); 32.1 isn't in opam and only
  a trimmed kernel+EVA is built. Needs `libyaml`/`pkg-config` and a C preprocessor. The
  vendor script fills Frama-C's empty `*.opam` placeholders so opam-monorepo can scan.

## Updating dependencies

For a third-party source that is **not** in the lock file (the git pins and the
tarballs — ppxlib, lwt, js_of_ocaml, pplacer, mcl, frama-c, the apron chain, cpdf,
menhir, rocq, alt-ergo's deps, …), the bump is a one-line edit to `sources.yml`
followed by `make setup`. Nothing else references the version.

For the lock file itself:

```bash
# 1. Modify dune-project if adding/removing packages
# 2. Re-lock in a switch that has the opam-monorepo plugin
#    (OPAMSWITCH selects it for this one command without changing your shell's switch)
OPAMSWITCH=<tools-switch> opam monorepo lock
# 3. Rebuild from scratch
make clean-all && make setup
# 4. Commit the updated lock file
git add macro-benches.opam.locked dune-project *.opam
git commit -m "Update vendored dependencies"
```

## Adding a new benchmark

1. Add a `(package ...)` declaration in `dune-project`.
2. Create an `.opam.template` if non-dune deps need `x-opam-monorepo-opam-provided`.
3. Re-lock: `opam monorepo lock`.
4. Create `benchmarks/<tool>/` with `<tool>.build.sh`, a `dune` file (if custom `.ml`),
   and input files.
5. Add every program to `benchmarks/manifest.yml` **in the same commit** — CI fails
   if a build script has no program entry (or vice versa). For a input-size ladder, list
   only the `_small` rung. A tool that ships disabled goes under `disabled:` with a
   reason instead.
6. Register it in your orchestrator config (running-ng's experiment YAML), with the
   same `args` string as the manifest.
7. Add it to the test-build list in `scripts/setup-monorepo.sh`.
8. Add a human page at `docs/benchmarks/<tool>.md`.
9. Test: `make clean-all && make setup`, then
   `ONLY="<prog>" bash scripts/ci-build-all.sh && ONLY="<prog>" bash scripts/ci-run-all.sh`.

---

## Backlog

Follow-up benchmarking work carried over from the old `TODO.md`. Append entries with
date, owner if known, and enough context that someone else can pick it up. The
coverage-gaps section above is the current authority on what the suite misses; the
first entry here is the prioritised plan for closing those gaps.

### Close runtime-feature coverage gaps — filed 2026-05-15

A source-grounded audit of every benchmark against the runtime mechanisms it exercises
turned up ten mechanisms no benchmark exercises hot (see "Coverage gaps" above).

Re-audited 2026-09-21 with a perf profile and an strace of every small rung. Two gaps
closed since filing: the **ephemeron data-field** (coq's `Compute` is `vm_compute`, and
the VM's symbol table is an `Ephemeron.K1`-with-data table) and **per-domain CPU
pinning** (patched into infer's DomainPool). `io_uring` stays a gap but is now measured
rather than assumed: eio creates a ring and issues 2 `io_uring_enter` per run. Two
gaps were added: **contended atomics** and **`Gc.finalise` proper**. The running-ng
selectors that error loudly are now `io_uring` and `ocaml_finalisers`; the `ephemerons`
and `kcas` selectors are gone (the first because it is covered, the second because the
tag named code nothing in the tree calls). The remaining gaps and candidate closures:

- Ephemeron data-field *churn* (`Ephemeron.K1.Hashtbl` in a loop): coq covers presence,
  not rate. Small dedicated benchmark, ~100-200 lines.
- Contended atomics under N domains: the part of the atomics story runtime work touches
  (fences, arm64 LSE, `make_contended`). Sandmark-style CAS contention driver, ~100 lines.
- An always-available multi-domain rung, so parallel-GC coverage does not rest solely on
  infer, which is network-vendored and needs a Java corpus.
- `Gc.finalise` at a measurable rate: only pplacer_testsuite registers any today.
- kcas / lock-free MCAS: standalone benchmark wrapping `Kcas_data.Hashtbl`/`Queue` under
  N-domain contention, ~150 lines; can vendor as a sibling to lavyek.
- Domainslib work-stealing: Sandmark `parallel_binarytrees` import (~200 lines).
- Forced `Gc.compact`/`Gc.full_major`: a `_compact` variant wrapping an existing
  allocation-heavy driver (compaction-vs-finalisers is the interesting story for owl_gc
  and liq_video_frames_pool).
- `Gc.alarm` callbacks: synthetic ~50-line driver.
- High-frequency `Sys.set_signal`: itimer-driven SIGALRM at ~1ms combined with an
  allocator-heavy driver.
- Pure-OCaml flambda-sensitive float kernel: Sandmark `nbody`/`raytracer`/`mandelbrot`
  import (~200 lines each; `nbody` is the canonical flambda one).
- `Bigarray` slicing/reshape: a `Genarray.slice_left`/`Array1.sub` micro-stressor, or
  fork owl_gc to slice-based access.
- Polling-points / safe-point density: tight no-alloc loop under an `Eio.Switch` with
  periodic cancellation pokes.
- Direct user `Effect.Deep.try_with` outside Eio: Sandmark `effects` microbench (~80 lines).

- Real io_uring traffic: an eio rung doing file or socket I/O rather than in-memory
  streams (lavyek's WAL writes used to do this).

Suggested order, cheapest signal first: `Gc.alarm` synthetic → `Gc.compact` variant →
Sandmark `nbody` → an always-available multi-domain rung → contended-atomics driver →
eio file-I/O rung → kcas synthetic. Status: not started, except that the tag block in
running-ng now records each of these as a `gap:` note where a tag exists for it.

### Investigate `ocamlc_self_compile` allocation regression on d8b — filed 2026-05-06

`ocamlc_self_compile` regresses ~+8% wall on d8bb46c across all flag combos but only drops
~5% RSS, unlike sibling RSS-winners (cpdf_*, menhir_sysver) that drop 20-40% RSS. On the
2026-05-03 monolith N=3 run, d8b allocates ~1.3 GB more minor-heap bytes for the same
deterministic compile (8.57 → 9.90 GB total, minor collections +15.6%, major −25%, RSS
−4.9%). By contrast cpdf_merge's total allocation is identical across versions and only RSS
moves (the canonical pacer story). So this is the workload allocating differently between
versions, not the pacer.

The old ephemeron hypothesis was **invalidated 2026-05-15**: `grep -rn Ephemeron typing/
bytecomp/ driver/ utils/` returns nothing in 5.4.1 and trunk; `btype.ml:46` uses
`Hashtbl.Make`. Leading hypotheses now: stdlib growth (more modules to typecheck per
compile), `Hashtbl` resize/per-entry overhead in `TypeHash`, `Marshal`/`Compression`
buffer behaviour for `.cmi`/`.cmo`, or the `Bigarray.Array1` emit-buffer growth policy.
Next steps: `OCAMLRUNPARAM=v=0x400` per-cycle GC log to see when the extra allocation lands;
reduce the workload to one module to test per-node vs fixed offset; statmemprof diff; bisect
5.4 → d8b. Status: not started.

### Domainslib / work-stealing N-domain benchmark — filed 2026-05-01, updated 2026-05-15

Lavyek (when enabled) provided N>2 domain shared-heap GC under contention plus io_uring, so
the remaining gap is specifically **work-stealing scheduler load**: nothing consumes
`Domainslib.Task.{run,parallel_for,async}`. Options: Sandmark `parallel_binarytrees` import
(preferred, ~200 lines, established shape), a synthetic tree-of-tasks driver under
`Domainslib.Task` (~150 lines), or Meta's `infer` (largest; open questions on
opam/dune-buildability and work-distribution pattern). Status: open; overlaps the
coverage-gaps entry.

### Re-enable `merlin_bench` once the upstream race is fixed — filed 2026-05-01

`merlin_bench` is vendored from the merlin-domains branch (PR #1890) and is the only
2-domain steady-state workload (main + typer worker). It's disabled: the typer-domain
handoff has a non-deterministic race that fires `Types.rev_log → Invalid -> assert false`
at N≥2 iterations on both 5.4.1 and d8bb46c. Full repro in
`benchmarks/merlin/UPSTREAM_BUG.md`. When picking up: watch PR #1890, re-vendor, flip the
programs list back on in running-ng, and re-validate (7 cram queries, ~16s at arg=4, ~1 GB
RSS, ~24% gc_overhead). Re-enabling moves the `domains` and `effects` tags from cold to exercised, and
would give contended atomics a home (there is no `atomics` tag: the mechanism has no
measurable coverage, see the matrix). Status: waiting on upstream fix.

### GC-parameter sweep on `liq_video_frames_pool` and related — filed 2026-05-01

Steps 1-2 resolved 2026-05-14: on the real liquidsoap pipeline (Ryzen 9 9950X), `M=250`
trades +10% RSS for −17% CPU, the predicted #14533 free-lunch shape in the large-M regime
(repro in the `offheap_M_o_sweep_2026_05_13.yml` results). Still pending: extend the sweep
to one bench per allocation-profile bucket (owl_gc, zarith_pi, liq_parse_typecheck,
ocamlc_self_compile — the last re-characterised 2026-05-15 as minor-heavy Hashtbl + Marshal
+ Bigarray, not ephemeron), then re-run the 8-variant cross-runtime comparison with each
bench at its per-runtime optimal `(s, o)` to see whether the apparent `zarith_pi` (16%) and
`ocamlc_self_compile` (10%) regressions shrink. Tooling: the `gc_sweep_all_versions.yml` and
`offheap_M_o_sweep_*.yml` running-ng configs. Status: steps 3-4 pending.
