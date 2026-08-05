# liq-video-frames

A synthetic benchmark that reproduces the allocation shape of the liquidsoap
"ai-radio" video pipeline. It is the reproducer for OCaml
[#14533](https://github.com/ocaml/ocaml/issues/14533) (and related #13123): a
streaming loop that allocates custom blocks backed by large off-heap buffers, where
the GC pacer's handling of that off-heap memory decides both CPU cost and RSS. Each
frame is three `Bigarray` `Char` YUV420 planes (~1.32 MiB). The `_pool` machinery
(`LIQ_POOL=1`, `pool_stubs.c`) registers each frame's byte size with the pacer via
`caml_alloc_custom_mem` but allocates no real buffer — mirroring ocaml-ffmpeg's
refcounted `av_frame_free` — while `LIQ_TOUCH=full` writes every pixel. This is the
only benchmark whose wall/RSS Pareto front moves with `custom_major_ratio` (M).

## Ladder

Input size = the **frame resolution** (`argv.2`/`argv.3` = width/height, at a fixed
15000 frames). A bigger frame registers a bigger off-heap size with the pacer per
frame, so the pacer forces proportionally more major cycles. Measured on OCaml
5.5.0, Ryzen 9 9950X (`fingerprint.sh` `v=0x400`; olly gc%/pause from
`perf_grp1|re-25|md-2`):

| rung | resolution | wall | RSS | gc% | major GC | max pause |
| --- | --- | --- | --- | --- | --- | --- |
| `_small` | 1080p | 5.6s | 107 MB | 94.6% | 1104 | 4.8 ms |
| `_default` | 4K | 22.5s | 116 MB | 93.6% | 4413 | 4.9 ms |
| `_large` | 8K | 101.5s | 151 MB | 79.1% | 16837 | 5.2 ms |

The **major-collection count grows with pixels²** (1104 → 16837) and gc% is extreme
(~80-95%) — the most major-GC-pacing-bound ladder in the suite, exactly the
`custom_major_ratio` (M) territory of #14533. Because the pool registers off-heap
bytes without allocating a real per-frame buffer, **RSS grows only modestly**
(107 → 151 MB) and `top_heap_words` is flat — read this ladder by its collection
counts and gc%, not RSS. Pauses stay small (~5 ms): the pacer does many small major
slices. A huge band is deferred.

## Legacy

Kept for reference, not run by default (`RUNNING_TAG=legacy`):

- `liq_video_frames_pool` — the FROZEN exact #14533 reproducer: the fixed 720p ×
  30000-frame pool input. Kept unchanged because it is the issue repro. Under M=250
  the refcounted-pool path drops ~17% CPU for +10% RSS (the "free lunch" shape);
  a single default-cell reading tells you little — the useful signal is a sweep over M.

## Notes

- Wall times are hardware-dependent (roughly 4-20s for the frozen repro); treat them
  as a range, not a target.
- The `_build-<runtime>` outputs are wrapper scripts. If you wipe the build dir,
  delete the wrapper outputs too so running-ng rebuilds the `.exe`.
- Background: the liquidsoap ai-radio blog post
  (https://www.liquidsoap.info/blog/2024-02-10-video-canvas-and-ai/) describes the
  real workload this stands in for.
