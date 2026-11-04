(* Coq input-size ladder rung (large): kernel reduction of a unary-nat tree size.
   make_tree 21 builds 2^21 nodes; tree_size reduces to a 2^21-deep unary nat,
   so coqc's kernel does allocation-heavy exponential reduction. Depth is the
   input size (small=19 ~8s, default=20 ~18s, large=21 ~42s on 5.4.1/Ryzen with
   rocq's own GC settings, i.e. OCAMLRUNPARAM unset). *)
Require Import Init.Nat.
Require Import Init.Peano.
Inductive big_tree : Type := Leaf : nat -> big_tree | Node : big_tree -> big_tree -> big_tree.
Fixpoint tree_size (t : big_tree) : nat := match t with Leaf _ => 1 | Node l r => 1 + tree_size l + tree_size r end.
Fixpoint make_tree (depth : nat) : big_tree := match depth with 0 => Leaf 0 | S d => Node (make_tree d) (make_tree d) end.
Compute tree_size (make_tree 21).
