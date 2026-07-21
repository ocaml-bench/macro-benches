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
