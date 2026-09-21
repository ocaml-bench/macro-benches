(* liq_video_frames.ml: synthetic GC-pacer reproducer for ocaml#14533 and #13123,
   modelling liquidsoap's video pipeline: three Bigarrays per frame sized like
   mm's Image.YUV420.create (Y 1280x720, U/V 640x360, ~1.32 MiB), each a custom
   block via caml_alloc_custom_mem. argv.1 = iteration count.
   Env vars (defaults in parentheses):
     LIQ_POOL=0|1                   (0)    fresh malloc (mm) vs ffmpeg-style refcounted pool
     LIQ_TOUCH=full|page|first|none (full) how the mutator writes planes
     LIQ_DW_MB=N                    (100)  OCaml-heap deadweight in MiB
     LIQ_NO_DEADWEIGHT=1            (off)  disable deadweight
     LIQ_PACE_FPS=fps               (off)  drift-free real-time frame pacing
     LIQ_CHURN=N                    (0)    short-lived OCaml allocs per iteration
   Toots' free-lunch shape reproduces with LIQ_POOL=1, LIQ_TOUCH=full. *)

(* Plane sizes match mm/imageYUV420.ml at 1280x720. LIQ_WIDTH/LIQ_HEIGHT are the
   input-size axis: a bigger frame scales the custom-block pacer's allocation unit. *)
let arg_or_env i env default =
  if Array.length Sys.argv > i then int_of_string Sys.argv.(i)
  else match Sys.getenv_opt env with Some s -> int_of_string s | None -> default
let frame_width = arg_or_env 2 "LIQ_WIDTH" 1280
let frame_height = arg_or_env 3 "LIQ_HEIGHT" 720
let y_bytes = frame_width * frame_height
let uv_bytes = ((frame_width + 1) / 2) * ((frame_height + 1) / 2)

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

(* Pool stub: registers `mem` bytes with the pacer via caml_alloc_custom_mem but
   allocates nothing, like ocaml-ffmpeg's refcounted AVFrame release. *)
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

(* Touch policy: `full` writes every pixel, `page` one byte per 4 KiB page,
   `first` only page 0, `none` leaves memory reserved but uncommitted. Only
   affects RSS in LIQ_POOL=0, where lingering frames occupy real memory. *)
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

(* Deadweight the major heap must carry through every cycle. *)
let deadweight =
  if deadweight_mb = 0 then [||]
  else Array.make (deadweight_mb * 1024 * 1024 / 8) 1

(* Short-lived churn: real liquidsoap allocates thousands of small values per
   frame, which drives minor GCs and bounds the lingering-frame queue. *)
let churn =
  if churn_count = 0 then fun () -> ()
  else fun () ->
    let lst = List.init churn_count (fun i -> ref i) in
    ignore (Sys.opaque_identity lst)

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
