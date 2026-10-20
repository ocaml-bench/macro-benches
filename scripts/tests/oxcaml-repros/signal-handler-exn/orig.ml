exception Timeout
let () =
  Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> raise Timeout));
  ignore (Unix.alarm 1);
  try while true do ignore (Sys.opaque_identity (ref 0)) done
  with Timeout -> exit 142
