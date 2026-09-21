(* like_bench.ml: pplacer's likelihood hot path (Felsenstein pruning over
   generalized likelihood vectors), lifted from tests/pplacer/test_like.ml minus
   its exact-value assertion. Input size is n_sites: the Glv are GSL-backed
   off-heap Bigarrays sized by n_sites, so the off-heap working set grows
   linearly with the column-replication factor; tree and taxa stay fixed.
   Env vars (defaults are the jtt protein test, 20 states):
     PPLACER_LIKE_DIR   (tests/data/like/jtt/)  data dir, with a trailing slash
     PPLACER_LIKE_FASTA (actin.fasta)           reference alignment in DIR
     PPLACER_LIKE_TREE  (actin.phy_phyml_tree.txt)  Newick tree in DIR
     PPLACER_LIKE_MULT  (1)                      column-replication factor
     PPLACER_LIKE_SCAN  (40)                     pendant-branch scan points (a fixed
                                                 constant, not the ladder axis)
   Paths are relative to CWD; the build.sh wrapper cd's into vendor/pplacer. *)

open Ppatteries
open Gmix_model
let add_zero_root_bl = Newick_gtree.add_zero_root_bl
module Glv = Model.Glv
module Like_stree = Like_stree.Make(Model)

let getenv_default k d = try Sys.getenv k with Not_found -> d

let () =
  let dir = getenv_default "PPLACER_LIKE_DIR" "tests/data/like/jtt/" in
  let fasta = getenv_default "PPLACER_LIKE_FASTA" "actin.fasta" in
  let tree_fname = getenv_default "PPLACER_LIKE_TREE" "actin.phy_phyml_tree.txt" in
  let mult = try int_of_string (Sys.getenv "PPLACER_LIKE_MULT") with _ -> 1 in
  let scan = try max 1 (int_of_string (Sys.getenv "PPLACER_LIKE_SCAN")) with _ -> 40 in
  let d str = dir ^ str in

  (* Scale n_sites by repeating every sequence K times; taxa and tree are untouched. *)
  let aln0 = Alignment.upper_aln_of_any_file (d fasta) in
  let aln =
    if mult <= 1 then aln0
    else Array.map
      (fun (name, seq) ->
        (name, String.concat "" (List.init mult (fun _ -> seq))))
      aln0
  in
  let tree = d tree_fname |> Newick_gtree.of_file |> add_zero_root_bl in
  let model =
    d "phylo_model.jplace"
    |> Json.of_file
    |> Jsontype.obj
    |> flip init_of_json aln
    |> Model.build aln
  in
  let n_sites = Alignment.length aln in
  Printf.printf "pplacer like_bench: %d taxa, %d sites (x%d), running...\n%!"
    (Array.length aln) n_sites mult;

  (* Felsenstein pruning over the tree, copied from test_like.ml. *)
  let like_aln_map =
    Like_stree.like_aln_map_of_data (Model.seq_type model) aln tree
  in
  let darr = Like_stree.glv_arr_for model tree n_sites in
  let parr = Glv_arr.mimic darr
  and snodes = Glv_arr.mimic darr in
  let util_glv = Glv.mimic (Glv_arr.get_one snodes) in
  Like_stree.calc_distal_and_proximal model tree like_aln_map
    util_glv ~distal_glv_arr:darr ~proximal_glv_arr:parr
    ~util_glv_arr:snodes;
  List.iter
    (Glv_arr.iter (Glv.perhaps_pull_exponent (-10)))
    [darr; parr;];
  let half_bl_fun loc = (Gtree.get_bl tree loc) /. 2. in
  Glv_arr.prep_supernodes model ~dst:snodes darr parr half_bl_fun;
  let utilv_nsites = Gsl.Vector.create n_sites
  and util_d = Glv.mimic darr.(0)
  and util_p = Glv.mimic parr.(0)
  and util_one = Glv.mimic darr.(0) in
  Glv.set_unit util_one;
  let acc = ref 0. in
  for i = 0 to (Array.length darr) - 1 do
    let d = darr.(i)
    and p = parr.(i)
    and sn = snodes.(i) in
    (* ML pendant-branch scan over 0.1x..2x the edge half-length, keeping the
       maximum: the placement optimisation, at fixed working set. *)
    let base_bl = half_bl_fun i in
    let best = ref neg_infinity in
    for g = 0 to scan - 1 do
      let f = 0.1 +. 1.9 *. (float_of_int g /. float_of_int (max 1 (scan - 1))) in
      let bl = base_bl *. f in
      Model.evolve_into model ~src:d ~dst:util_d bl;
      Model.evolve_into model ~src:p ~dst:util_p bl;
      let ll = Model.slow_log_like3 model util_d util_p util_one in
      if ll > !best then best := ll
    done;
    acc := !acc +. !best;
    acc := !acc +. Glv.logdot utilv_nsites sn util_one;
  done;
  (* Keep the whole computation live and observable. *)
  Printf.printf "pplacer like_bench: done, sum_log_like=%g\n%!" !acc
