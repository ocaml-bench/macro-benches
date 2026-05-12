/* pool_stubs.c — simulate ffmpeg's refcounted-frame-pool semantics.
 *
 * Real ocaml-ffmpeg wraps each AVFrame in a custom block via
 * caml_alloc_custom_mem(..., mem = sum_of_buf_sizes). The finalize_frame
 * callback does av_frame_free(), which decrements buffer refcounts —
 * not free(). The underlying buffer stays alive in ffmpeg's pool, so
 * real RSS is bounded by the pool size (~8–16 buffers), even though
 * the GC pacer "sees" each frame as a fresh `mem`-sized allocation.
 *
 * This stub mimics that: register `size` bytes with the major-GC pacer
 * via caml_alloc_custom_mem, but allocate no actual buffer. The pacer
 * decrements on finalise automatically. RSS stays bounded to whatever
 * shared buffer the OCaml side chooses to "touch". */

#define CAML_NAME_SPACE
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

static struct custom_operations pool_ops = {
    "liq_video_frames.pool_frame",
    custom_finalize_default,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_fixed_length_default};

CAMLprim value liq_pool_alloc(value v_size) {
  CAMLparam1(v_size);
  CAMLlocal1(ret);
  intnat sz = Long_val(v_size);
  ret = caml_alloc_custom_mem(&pool_ops, sizeof(intnat), sz);
  CAMLreturn(ret);
}
