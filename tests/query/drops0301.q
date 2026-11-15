## `query drops FILE:LINE` (0.30.1, RT-34; tests/query/drops0301/): a
## line of a function with a `requires` and an `ensures` is in f (the
## wrapper that checks), f$pre (the requires' checks) and f$body (the
## body itself): the drops of each are shown, so the body's `for`, which
## moves the Vec out, drops it once (`__for_it`), never `a` again.
$ drops main.vl:22
drops0301/main.vl:22 in f
  17:1  drop(_4) [removed]  a temporary (17:1): Vec<D, Gpa>
  25:1  drop(_1) [removed]  a: Vec<D, Gpa>
drops0301/main.vl:22 in f$pre
  (no drops: nothing it holds needs one)
drops0301/main.vl:22 in f$body
  22:16  drop(_10) [removed]  a temporary (22:14): D
  23:5  drop(_5) [removed]  a temporary (21:5): Vec<D, Gpa>
  23:5  drop(_9) [removed]  d: D
  23:5  drop(_6) [removed]  a temporary (21:5): Option<D>
  23:5  drop(_4) [kept]  __for_it: IntoIter<D, Gpa>
  23:5  drop(_3) [removed]  __for_seq: Vec<D, Gpa>
  23:6  drop(_6) [kept]  a temporary (21:5): Option<D>
  25:1  drop(_1) [removed]  a: Vec<D, Gpa>
## (round 2) a generic function's instances are one, shown by the first
## (as before 0.30.1); a #[multiversion] function's closure and its
## copy in the version are named with the function each is in.
$ drops main.vl:35
drops0301/main.vl:35 in g<i64>
  37:1  drop(_1) [kept]  v: Vec<i64, Gpa>
$ drops main.vl:43 -C target-cpu=generic
drops0301/main.vl:43 in closure(D) -> i64 at drops0301/main.vl:43:13, in h
  43:22  drop(_1) [kept]  d: D
drops0301/main.vl:43 in closure(D) -> i64 at drops0301/main.vl:43:13, in h$mv0
  43:22  drop(_1) [kept]  d: D
