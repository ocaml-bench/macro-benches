# liq-video-frames

A synthetic benchmark that reproduces the allocation shape of the liquidsoap
"ai-radio" video pipeline. It is the reproducer for OCaml
[#14533](https://github.com/ocaml/ocaml/issues/14533) (and related #13123):
a streaming loop that allocates a lot of custom blocks backed by large
off-heap buffers, where the GC pacer's handling of that off-heap memory
decides both CPU cost and RSS.

## What it runs

The source is `benchmarks/liq-video-frames/liq_video_frames.ml` plus a small
C stub (`pool_stubs.c`). Each iteration models one 720p video frame: three
`Bigarray` `Char` planes sized like `mm/Image.YUV420.create`, namely a
1280x720 Y plane (921600 B) and two 640x360 chroma planes (230400 B each),
for about 1.32 MiB per frame.

The build script produces two wrappers:

| Wrapper | Env set | Models |
|---|---|---|
| `liq_video_frames-<runtime>` | none (defaults) | fresh-malloc per frame |
| `liq_video_frames_pool-<runtime>` | `LIQ_POOL=1`, `LIQ_TOUCH=full` | ffmpeg-style refcounted pool |

The assigned program is the `_pool` variant. `LIQ_POOL=1` routes allocation
through `pool_stubs.c`: it registers the frame's byte size with the GC pacer
via `caml_alloc_custom_mem` but allocates no real buffer, mirroring how
ocaml-ffmpeg's `av_frame_free` decrements a refcount instead of freeing.
`LIQ_TOUCH=full` writes every pixel, keeping the real pipeline's mutator
cost.

The single argument is the number of frames to allocate (`Sys.argv.(1)`).
The suite runs it at 30000 frames, which gives roughly 4-20s of wall time
depending on hardware. Note that the program's own default is 1 frame; the
30000 comes from the runner, not from a default inside the program.

Env knobs a human might flip:

- `LIQ_POOL` (0/1, default 0): fresh-malloc vs refcounted-pool semantics.
- `LIQ_TOUCH` (full/page/first/none, default full): how much of each plane
  the mutator writes.
- `LIQ_DW_MB` (default 100): persistent OCaml-heap "deadweight" in MiB,
  standing in for liquidsoap's loaded stdlib and script graph.
- `LIQ_NO_DEADWEIGHT=1`: turn the deadweight off entirely.
- `LIQ_CHURN` (default 0): short-lived OCaml allocations per iteration.
- `LIQ_PACE_FPS` (default off): drift-free real-time frame pacing.

## Knob-A ladder (frame resolution)

The frozen `liq_video_frames_pool` bench is the exact #14533 repro (30000 720p frames).
The `liq_video_frames_pool_{small,default,large}` rungs keep that pool/pacer machinery but
scale the **frame resolution** (`argv.2`/`argv.3` = width/height) at a fixed 15000 frames.
A bigger frame means `pool_stubs.c` registers a bigger off-heap size with the pacer via
`caml_alloc_custom_mem` on every frame, so the pacer forces proportionally **more major
cycles** — the size of the custom-block allocation is the Knob-A axis. Measured on OCaml
5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly gc%/pause from `perf_grp1|re-25|md-2`):

| rung | resolution | wall | gc% | RSS | minor GC | major GC | max pause |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `_small` | 1080p | 5.6s | 94.6% | 107 MB | 2.2k | 1104 | 4.8 ms |
| `_default` | 4K | 22.5s | 93.6% | 116 MB | 8.8k | 4413 | 4.9 ms |
| `_large` | 8K | 101.5s | 79.1% | 151 MB | 34k | 16837 | 5.2 ms |

The **major-collection count grows with pixels²** (1104 → 4413 → 16837), and gc% is extreme
(~80–95 %) — this is the most major-GC-pacing-bound ladder in the suite, exactly the
`custom_major_ratio` (M) territory of #14533. Because the pool registers off-heap bytes
without allocating a real per-frame buffer, **RSS grows only modestly** (107 → 151 MB, the
deadweight plus the one shared buffer) and `top_heap_words` is flat — read this ladder by its
**collection counts and gc%**, not RSS (the off-heap caveat). Pauses stay small (~5 ms): the
pacer does many small major slices rather than a few big ones. A huge band is deferred.

## What it stresses

- The large-allocation custom-block path for Bigarrays, which is a different
  path from owl's small matrices.
- Off-heap memory accounting in the major-heap pacer. `caml_alloc_custom_mem`
  reports the off-heap size to the GC, which feeds `space_overhead` and
  `custom_major_ratio` (M) decisions. This is the only benchmark in the suite
  whose wall/RSS Pareto front actually moves with M.
- The interaction between the persistent deadweight and the pacer, which sets
  how much major-heap headroom there is.

## Reading the results

Both wall time and RSS are sensitive to M (`custom_major_ratio`). Under
M=250 the refcounted-pool path drops CPU noticeably with no RSS growth: the
shared pool buffer caps committed memory no matter how the GC schedules
release. That is the "free lunch" shape from #14533, and it only shows up in
the large-M regime. At the default `(M=44, o=120)` the variant sits close to
5.4.1 noise.

Because of that, a single default-cell reading tells you very little here.
The useful signal is a sweep over M, comparing wall vs RSS. A large-M CPU
drop with flat RSS means the pacer changes kept the pool fast path intact;
movement at the default cell means the `caml_alloc_custom_mem` accounting or
pacer policy itself changed.

## Notes

- The wall times are hardware-dependent; treat "4-20s" as a range, not a
  target.
- The `_build-<runtime>` outputs are wrapper scripts. If you wipe the build
  dir, delete the wrapper outputs too so running-ng rebuilds the `.exe`.
- Background reading: the liquidsoap ai-radio blog post
  (https://www.liquidsoap.info/blog/2024-02-10-video-canvas-and-ai/)
  describes the real workload this stands in for.
