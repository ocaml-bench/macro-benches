(* liq_bench.ml — benchmark liquidsoap-lang parser + typechecker.
   Repeatedly parses and typechecks a large liquidsoap script. *)

let script = {|
# Liquidsoap benchmark workload: exercises parser, typechecker, evaluator
# on a mix of language features: functions, pattern matching, lists,
# records, string interpolation, and recursive definitions.

def fib(n) =
  if n <= 1 then n
  else fib(n - 1) + fib(n - 2)
  end
end

def factorial(n) =
  if n <= 0 then 1
  else n * factorial(n - 1)
  end
end

def map(f, l) =
  list.case(l,
    [],
    fun (h, t) -> list.add(f(h), map(f, t))
  )
end

def filter(f, l) =
  list.case(l,
    [],
    fun (h, t) ->
      if f(h) then list.add(h, filter(f, t))
      else filter(f, t)
      end
  )
end

def fold(f, acc, l) =
  list.case(l,
    acc,
    fun (h, t) -> fold(f, f(acc, h), t)
  )
end

def range(a, b) =
  if a >= b then []
  else list.add(a, range(a + 1, b))
  end
end

let nums = range(0, 100)
let squares = map(fun (x) -> x * x, nums)
let evens = filter(fun (x) -> x mod 2 == 0, nums)
let sum = fold(fun (acc, x) -> acc + x, 0, nums)
let product_mod = fold(fun (acc, x) -> (acc * (x + 1)) mod 1000000007, 1, range(1, 50))

# String manipulation
def repeat_string(s, n) =
  if n <= 0 then ""
  else s ^ repeat_string(s, n - 1)
  end
end

let greeting = repeat_string("hello ", 10)

# Nested function definitions
def compose(f, g) =
  fun (x) -> f(g(x))
end

let double = fun (x) -> x * 2
let inc = fun (x) -> x + 1
let double_then_inc = compose(inc, double)
let result = double_then_inc(21)

# Multiple let bindings to exercise the type environment
let a = 1
let b = a + 1
let c = b + a
let d = c * b
let e = d - c + b - a
let f = fib(10)
let g = factorial(8)
|}

let iterations = ref 200

let () =
  if Array.length Sys.argv > 1 then
    iterations := int_of_string Sys.argv.(1);
  for _ = 1 to !iterations do
    let parsed, _term = Liquidsoap_lang.Runtime.parse script in
    ignore (Liquidsoap_lang.Runtime.type_term parsed)
  done
