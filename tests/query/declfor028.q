## (0.28.0, gap 97) `query effects` and the check of a declaration agree
## on a `for`: the program's functions are all declared (#[pure],
## #[no_alloc], #[no_io], #[effects(..)]) and check without an error (a
## failed check would print `warning query.program-errors` here); the
## sets are within the declarations, and `--why interior` finds no write
## through a shared reference in a #[pure] loop over a slice.
$ effects crate declfor028/main.vl
crate::mean	none
crate::sum_ref	none
crate::sum_copied	none
crate::sum_index	none
crate::sum_vec	none
crate::sum_vec_iter	none
crate::bump	panic
crate::tri	none
crate::tri_incl	none
crate::weighted	none
crate::dot	none
crate::evens	none
crate::doubled	none
crate::back	none
crate::pairs	panic
crate::letters	panic diverge
crate::show	io static panic
crate::collect	alloc(Gpa) panic
crate::main	alloc(Gpa) io static panic diverge
$ effects mean --why interior declfor028/main.vl
crate::mean	none
  (not: interior)
$ effects sum_vec --why interior declfor028/main.vl
crate::sum_vec	none
  (not: interior)
$ effects crate --has interior declfor028/main.vl
note query.empty: no function has interior
