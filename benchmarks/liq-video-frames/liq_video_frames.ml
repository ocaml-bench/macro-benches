(* liq_video_frames.ml — synthetic reproduction of the allocation pattern
   from ocaml/ocaml#13123 + the liquidsoap "ai-radio" workload described
   in https://www.liquidsoap.info/blog/2024-02-10-video-canvas-and-ai/.

   Pattern:
     - Persistent "deadweight" (mimics liquidsoap's loaded standard
       library + script state) holds ~320 MB live for the whole run.
     - Tight loop allocates 1280×720 RGBA8 video frames as Bigarray.
       Each frame is ~3.5 MiB of off-heap memory wrapped in a custom
       block with a finaliser — mechanically the same shape as the
       ffmpeg-allocated frames liquidsoap streams in production.
     - Each frame is touched once and immediately discarded. They die
       in the minor heap if the GC pacer is keeping up.

   What it probes (and is not):
     - This is a *memory-footprint* benchmark, not a compute benchmark.
       The headline metrics are max_rss_kb and the minor:major collection
       ratio. Wall time is informative as a "did the GC pacer keep up?"
       summary but is not the primary signal.
     - In OCaml 5.x with default OCAMLRUNPARAM (space_overhead=120 in
       5.4, 5.5-beta default behaviour under investigation), the major
       heap grows several × what 4.14 would let it grow to. Setting
       space_overhead=40 (the suggested fix in #13123) brings it back
       in line.
     - Sys.argv.(1) is the iteration count (in-process loop). Default
       is calibrated to land in the macrobench 5–60 s wall-time
       envelope on obelisk-class hardware.

   What it isn't:
     - There are no Unix.sleepf calls. The original repro uses 40 ms
       sleeps to mimic real-time playback, but pacing inflates wall
       time without exercising the GC, and would push gc_overhead
       below the macrobench envelope. The pacer behaviour we care
       about manifests as long as we allocate enough relative to the
       major-heap budget — which we do. *)

let frame_width = 1280
let frame_height = 720
let bytes_per_pixel = 4 (* RGBA8 *)
let frame_bytes = frame_width * frame_height * bytes_per_pixel

(* One video frame ≈ 3.5 MiB of off-heap memory. Bigarray.Array1.create
   wraps malloc'd storage in an OCaml custom block with a finaliser
   that frees it — identical machinery to ffmpeg's frame buffers when
   they cross into OCaml via Owl/Ctypes/etc. *)
let alloc_frame () =
  Bigarray.Array1.create Bigarray.Char Bigarray.c_layout frame_bytes

(* Fill the entire buffer so every page is committed (RSS, not just
   VSZ). This is faithful to real ffmpeg-decoded frames — every pixel
   is touched. Bigarray.Array1.fill is a memset; ~3.5 MiB of memory
   bandwidth per frame ≈ 0.35 ms at typical DRAM speeds, which puts
   the per-iteration cost in the right range to land the macrobench
   wall-time envelope without a Unix.sleepf. *)
let touch f = Bigarray.Array1.fill f 'X'

(* Persistent deadweight: 40 * 1024 * 1024 OCaml ints ≈ 320 MiB live
   on 64-bit. Matches the value used in the refined repro Romain
   posted in the issue thread. The point is that the major heap needs
   to *contain* this through every collection cycle without growing
   to 4× its size due to space_overhead. Bound at module level so
   the GC can't reclaim it. Disable with LIQ_NO_DEADWEIGHT=1 to see
   the no-deadweight baseline (the regression typically does not
   reproduce without it — it's the persistent live data that exposes
   the pacer's response to space_overhead). *)
let deadweight =
  if Sys.getenv_opt "LIQ_NO_DEADWEIGHT" = Some "1" then [||]
  else Array.make (40 * 1024 * 1024) 1

let () =
  let n =
    if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 1
  in
  for _ = 1 to n do
    let f = alloc_frame () in
    touch f
  done;
  (* Force a use of `deadweight` so the binding can't be DCE'd. The
     Sys.opaque_identity is belt-and-braces against future inlining. *)
  ignore (Sys.opaque_identity deadweight)
