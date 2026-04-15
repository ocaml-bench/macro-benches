(* Rocq Corelib stress test — uses only Corelib, no stdlib *)
(* Exercises kernel reduction, GC via large term construction *)
Require Import Init.Nat.
Require Import Init.Peano.

(* Fibonacci — forces kernel to reduce deeply recursive terms *)
Fixpoint fib (n : nat) : nat :=
  match n with
  | 0 => 0
  | S 0 => 1
  | S (S m as p) => fib p + fib m
  end.

(* fib 25 = 75025 — ~10s of kernel reduction *)
Compute fib 25.

(* Sum to n — linear recursion but large result *)
Fixpoint sum_to (n : nat) : nat :=
  match n with
  | 0 => 0
  | S m => n + sum_to m
  end.

Compute sum_to 2000.

(* Ackermann — super-exponential growth, heavy GC *)
Fixpoint ack (m : nat) : nat -> nat :=
  match m with
  | 0 => S
  | S m' => fix ack_m (n : nat) : nat :=
    match n with
    | 0 => ack m' 1
    | S n' => ack m' (ack_m n')
    end
  end.

(* ack 3 10 = 8189 *)
Compute ack 3 10.

(* Large inductive tree — exercises GC allocation patterns *)
Inductive big_tree : Type :=
  | Leaf : nat -> big_tree
  | Node : big_tree -> big_tree -> big_tree.

Fixpoint tree_size (t : big_tree) : nat :=
  match t with
  | Leaf _ => 1
  | Node l r => 1 + tree_size l + tree_size r
  end.

Fixpoint make_tree (depth : nat) : big_tree :=
  match depth with
  | 0 => Leaf 0
  | S d => Node (make_tree d) (make_tree d)
  end.

(* tree of depth 15 = 65535 nodes *)
Compute tree_size (make_tree 15).
