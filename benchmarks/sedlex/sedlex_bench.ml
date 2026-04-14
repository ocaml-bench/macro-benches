(* Sedlex benchmark: Unicode-aware lexer processing a large input.
   Exercises lexer table lookup, string allocation, and GC via
   repeated tokenization of a generated input stream. *)

let digit = [%sedlex.regexp? '0'..'9']
let letter = [%sedlex.regexp? 'a'..'z' | 'A'..'Z' | '_']
let ident = [%sedlex.regexp? letter, Star (letter | digit)]
let number = [%sedlex.regexp? Plus digit, Opt ('.', Plus digit)]
let whitespace = [%sedlex.regexp? Plus (' ' | '\t' | '\n' | '\r')]
let string_char = [%sedlex.regexp? Compl ('"' | '\\')]
let string_lit = [%sedlex.regexp? '"', Star string_char, '"']
let comment = [%sedlex.regexp? "//", Star (Compl '\n')]
let operator = [%sedlex.regexp? '+' | '-' | '*' | '/' | '=' | '<' | '>' | '!' | '&' | '|']
let punct = [%sedlex.regexp? '(' | ')' | '{' | '}' | '[' | ']' | ';' | ',' | '.']

type token =
  | IDENT of string
  | NUMBER of string
  | STRING of string
  | OPERATOR of string
  | PUNCT of char
  | COMMENT
  | WS
  | EOF
  | UNKNOWN of string

let rec tokenize buf acc =
  match%sedlex buf with
  | whitespace -> tokenize buf (WS :: acc)
  | comment -> tokenize buf (COMMENT :: acc)
  | ident -> tokenize buf (IDENT (Sedlexing.Utf8.lexeme buf) :: acc)
  | number -> tokenize buf (NUMBER (Sedlexing.Utf8.lexeme buf) :: acc)
  | string_lit -> tokenize buf (STRING (Sedlexing.Utf8.lexeme buf) :: acc)
  | operator -> tokenize buf (OPERATOR (Sedlexing.Utf8.lexeme buf) :: acc)
  | punct -> tokenize buf (PUNCT (Sedlexing.Utf8.lexeme buf).[0] :: acc)
  | eof -> List.rev (EOF :: acc)
  | any -> tokenize buf (UNKNOWN (Sedlexing.Utf8.lexeme buf) :: acc)
  | _ -> assert false

(* Generate a large pseudo-code input *)
let generate_input n =
  let buf = Buffer.create (n * 80) in
  for i = 0 to n - 1 do
    Buffer.add_string buf (Printf.sprintf "let var_%d = func_%d(%d, %d.%d) + %d;\n"
      i (i mod 100) (i * 7) (i mod 1000) (i mod 100) ((i + 1) * 3));
    if i mod 10 = 0 then
      Buffer.add_string buf (Printf.sprintf "// comment line %d\n" i);
    if i mod 5 = 0 then
      Buffer.add_string buf (Printf.sprintf "let s_%d = \"string value %d\";\n" i i)
  done;
  Buffer.contents buf

let () =
  let n_lines = try int_of_string Sys.argv.(1) with _ -> 100_000 in
  let input = generate_input n_lines in
  Printf.printf "Input: %d bytes, %d lines\n%!" (String.length input) n_lines;

  let buf = Sedlexing.Utf8.from_string input in
  let tokens = tokenize buf [] in
  Printf.printf "Tokens: %d\n%!" (List.length tokens);

  (* Count token types *)
  let n_ident = ref 0 and n_num = ref 0 and n_str = ref 0 in
  List.iter (function
    | IDENT _ -> incr n_ident
    | NUMBER _ -> incr n_num
    | STRING _ -> incr n_str
    | _ -> ()
  ) tokens;
  Printf.printf "Idents: %d, Numbers: %d, Strings: %d\n%!"
    !n_ident !n_num !n_str
