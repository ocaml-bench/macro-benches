(*
 * Copyright (c) 2009-2013, Monoidics ltd.
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd

let is_yes = String.equal "yes"

let is_not_no = Fn.non (String.equal "no")

let major = 1

let minor = 3

let patch = 0

let commit = "5ea35c6b82"

let branch = "inferbench-v1.0"

type build_platform = Linux | Darwin | Windows

let build_platform = Darwin

let is_release = is_yes "no"

let tag = Printf.sprintf "v%d.%d.%d" major minor patch

let versionString = if is_release then tag else Printf.sprintf "%s-%s" tag commit

let versionJson =
  String.concat ~sep:"\n"
    [ "{"
    ; ("\"major\": " ^ string_of_int major ^ ", ")
    ; ("\"minor\": " ^ string_of_int minor ^ ", ")
    ; ("\"patch\": " ^ string_of_int patch ^ ", ")
    ; ("\"commit\": \"" ^ commit ^ "\", ")
    ; ("\"branch\": \"" ^ branch ^ "\", ")
    ; ("\"tag\": \"" ^ tag ^ "\"")
    ; "}" ]

let clang_enabled = is_yes "no"

let erlang_enabled = is_yes "no"

let hack_enabled = is_yes "no"

let java_enabled = is_yes "yes"

let java_version = int_of_string_opt "26"

let xcode_enabled = is_not_no "xcode-select"

let man_pages_last_modify_date = "2026-07-24"

let python_exe = "python3"

let python_next_exe = "no"

let python_enabled = is_yes "no"

let rust_enabled = is_yes "no"

let swift_enabled = is_yes "no"

;;
