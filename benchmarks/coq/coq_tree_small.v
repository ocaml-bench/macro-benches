(* Coq input-size ladder rung (small): kernel reduction of a unary-nat tree size.
   make_tree 17 builds 2^17 nodes; tree_size reduces to a 2^17-deep unary nat,
   so coqc's kernel does allocation-heavy exponential reduction. Depth is the
   input size (small=17 ~5s, default=18 ~19s, large=19 ~68s on 5.5.0/Ryzen). *)
Require Import Init.Nat.
Require Import Init.Peano.
Inductive big_tree : Type := Leaf : nat -> big_tree | Node : big_tree -> big_tree -> big_tree.
Fixpoint tree_size (t : big_tree) : nat := match t with Leaf _ => 1 | Node l r => 1 + tree_size l + tree_size r end.
Fixpoint make_tree (depth : nat) : big_tree := match depth with 0 => Leaf 0 | S d => Node (make_tree d) (make_tree d) end.
Compute tree_size (make_tree 17).
