(* liq_video_frames.ml — synthetic GC-pacer reproducer for ocaml#14533 and #13123.
   Models the allocation pattern of the liquidsoap "ai-radio" video pipeline
   described at https://www.liquidsoap.info/blog/2024-02-10-video-canvas-and-ai/.

   Faithfulness map (what we model from the real workload):

   - Frame format. The real pipeline renders to YUV420 at 1280×720 via mm's
     Image.YUV420.create, which allocates three aligned Bigarrays (Y, U, V
     planes) via caml_mm_ba_alloc → caml_alloc_custom_mem. Each plane is a
     separate custom block with its own pacer accounting and finaliser.
     We allocate three Bigarrays of the same sizes per iteration:
       Y  = 1280 × 720         = 921 600 B  (~0.88 MiB)
       UV = 640  × 360 each    = 230 400 B  (~0.22 MiB)
     Total ~1.32 MiB per frame committed.

   - Allocation lifecycle. mm's YUV420 buffers are fresh-malloc per frame.
     ocaml-ffmpeg's AVFrames are pooled (refcounted, backed by ffmpeg's
     internal pool — `av_frame_free` decrements rather than `free`s).
     LIQ_POOL=0 (default) models the mm path; LIQ_POOL=1 models the
     AVFrame path. Real liquidsoap mixes both.

   - Deadweight. Persistent OCaml-heap state (loaded stdlib + script
     graph). LIQ_DW_MB sets it; docker measurements of the real workload
     settle near 365 MiB total RSS on 5.4, mostly mapping-backed.

   Env vars (defaults in parentheses):
     LIQ_POOL=0|1             (0)    fresh-malloc vs ffmpeg-pool semantics
     LIQ_TOUCH=full|page|first|none (full)  how the mutator writes planes
     LIQ_DW_MB=N              (100)  OCaml-heap deadweight in MiB
     LIQ_NO_DEADWEIGHT=1      (off)  disable deadweight entirely
     LIQ_PACE_FPS=fps         (off)  drift-free real-time frame pacing
     LIQ_CHURN=N              (0)    short-lived OCaml allocs per iteration

   Argument: in-process iteration count (Sys.argv.(1)).

   What this synthetic does *not* model: liquidsoap's full streaming-pipeline
   OCaml-heap churn (closures, refs, list operations per output frame from
   operator composition). LIQ_CHURN exposes a knob for this but its
   contribution depends on the specific GC interactions — see comments
   inline. The cleanest reproduction of toots' free-lunch shape uses
   LIQ_POOL=1, LIQ_TOUCH=full. *)

(* Plane sizes match mm/imageYUV420.ml for 1280×720. *)
let frame_width = 1280
let frame_height = 720
let y_bytes = frame_width * frame_height
let uv_bytes = ((frame_width + 1) / 2) * ((frame_height + 1) / 2)

(* Env-var reads ----------------------------------------------------------- *)

let pool_mode = Sys.getenv_opt "LIQ_POOL" = Some "1"

let touch_mode =
  match Sys.getenv_opt "LIQ_TOUCH" with
  | None | Some "full" -> `Full
  | Some "page" -> `Page
  | Some "first" -> `First
  | Some "none" -> `None
  | Some other ->
      failwith ("LIQ_TOUCH=" ^ other ^ " not recognised (full|page|first|none)")

let deadweight_mb =
  if Sys.getenv_opt "LIQ_NO_DEADWEIGHT" = Some "1" then 0
  else
    match Sys.getenv_opt "LIQ_DW_MB" with
    | Some s -> int_of_string s
    | None -> 100

let pace_delay =
  match Sys.getenv_opt "LIQ_PACE_FPS" with
  | Some s -> Some (1.0 /. float_of_string s)
  | None -> None

let churn_count =
  match Sys.getenv_opt "LIQ_CHURN" with
  | Some s -> int_of_string s
  | None -> 0

(* Allocation: pool vs fresh ---------------------------------------------- *)

(* Pool stub: registers `mem` bytes with the GC pacer via caml_alloc_custom_mem
   but allocates no buffer. Mimics ocaml-ffmpeg's value_of_frame +
   av_frame_free, where finalize decrements an AVBufferRef refcount rather
   than freeing memory. *)
type pool_handle
external pool_alloc : int -> pool_handle = "liq_pool_alloc"

let shared_y, shared_u, shared_v =
  let mk size =
    Bigarray.Array1.create Bigarray.Char Bigarray.c_layout
      (if pool_mode then size else 0)
  in
  mk y_bytes, mk uv_bytes, mk uv_bytes

let alloc_frame () =
  if pool_mode then begin
    ignore (Sys.opaque_identity (pool_alloc y_bytes));
    ignore (Sys.opaque_identity (pool_alloc uv_bytes));
    ignore (Sys.opaque_identity (pool_alloc uv_bytes));
    (shared_y, shared_u, shared_v)
  end else
    ( Bigarray.Array1.create Bigarray.Char Bigarray.c_layout y_bytes,
      Bigarray.Array1.create Bigarray.Char Bigarray.c_layout uv_bytes,
      Bigarray.Array1.create Bigarray.Char Bigarray.c_layout uv_bytes )

(* Touch policy. `full` writes every pixel (faithful to decode+render+encode
   passes on real frames). `page` writes one byte per 4 KiB page (commits
   every page without the memset bandwidth). `first` commits only page 0.
   `none` skips the mutator — reserved-but-uncommitted memory. Touching
   beyond `first` changes RSS only in LIQ_POOL=0, where lingering frames
   under M=250 occupy real memory; in LIQ_POOL=1 the shared buffer is the
   same regardless of touch policy. *)
let touch_one : (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t -> unit =
  let page = 4096 in
  match touch_mode with
  | `None -> fun _ -> ()
  | `First -> fun b -> if Bigarray.Array1.dim b > 0 then Bigarray.Array1.set b 0 'X'
  | `Page ->
      fun b ->
        let n = Bigarray.Array1.dim b in
        let i = ref 0 in
        while !i < n do Bigarray.Array1.set b !i 'X'; i := !i + page done
  | `Full -> fun b -> if Bigarray.Array1.dim b > 0 then Bigarray.Array1.fill b 'X'

let touch (y, u, v) = touch_one y; touch_one u; touch_one v

(* Persistent OCaml-heap deadweight. Forces the major heap to *contain*
   this through every collection cycle. *)
let deadweight =
  if deadweight_mb = 0 then [||]
  else Array.make (deadweight_mb * 1024 * 1024 / 8) 1

(* Per-iteration OCaml-heap churn — short-lived list of refs. Real liquidsoap
   produces thousands of small allocs per output frame from operator
   composition; that pressure drives minor GCs on a regular cadence,
   running major slice work and bounding the lingering-frame queue. The
   net effect on the M=250 speedup ratio is workload-dependent. *)
let churn =
  if churn_count = 0 then fun () -> ()
  else fun () ->
    let lst = List.init churn_count (fun i -> ref i) in
    ignore (Sys.opaque_identity lst)

(* Main loop -------------------------------------------------------------- *)

let () =
  let n = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 1 in
  let start = Unix.gettimeofday () in
  for i = 1 to n do
    touch (alloc_frame ());
    churn ();
    match pace_delay with
    | None -> ()
    | Some d ->
        let target = start +. d *. float_of_int i in
        let now = Unix.gettimeofday () in
        if now < target then Unix.sleepf (target -. now)
  done;
  ignore (Sys.opaque_identity deadweight)
