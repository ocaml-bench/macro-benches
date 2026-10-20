let timed_out = Atomic.make false
let () =
  Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> Atomic.set timed_out true));
  ignore (Unix.alarm 1);
  while not (Atomic.get timed_out) do ignore (Sys.opaque_identity (ref 0)) done;
  exit 142
