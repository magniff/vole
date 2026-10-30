## `query drops FILE:LINE` (0.26.1, places-ir.md §8 step 9;
## tests/query/drops0261/): a function's drops as the places IR decides
## them (kept, removed, under a flag, opened into its parts), each with
## where it runs and what it drops; the function at a line inside it, a
## line outside every body, a line past the file's end.
$ drops main.vl:22
drops0261/main.vl:22 in pick
  31:13  drop(_12) [kept]  t: D
  34:5  drop(_12) [kept]  t: D
  35:33  drop(_21) [removed]  a temporary (35:22): D
  35:33  drop(_20) [open]  a temporary (35:18): (D, D)
  35:33  drop(_20.1) [kept]  a temporary (35:18): D
  37:1  drop(_22) [kept]  x: D
  37:1  drop(_5) [kept]  all: Vec<D>
  37:1  drop(_4) [removed]  b: D
  37:1  drop(_3) [flag _26]  a: D
$ drops main.vl:18 main.vl:12
drops0261/main.vl:18 in keep
  19:1  drop(_2) [removed]  d: D
drops0261/main.vl:12 in mk
  15:1  drop(_3) [removed]  v: Vec<i64>
$ drops main.vl:3
error query.no-match: main.vl:3 is in no function with a body in the places IR (a generic one never instantiated, C's, or one with errors)
try: volec query show main.vl:3
[exit 1]
$ drops main.vl:99
error query.no-match: drops0261/main.vl has no line 99
[exit 1]
