## `query contracts` (0.27.2.1, contracts-effects.md C7.6): a trait's
## method's clauses, then each impl's, the trait's copies marked; a
## function's; `query items --undeclared` (E3.6).
$ contracts Pick::pick contracts02721/main.vl
crate::Pick::pick	contracts02721/main.vl:3:8
  requires i >= 0	contracts02721/main.vl:4:9
impl Pick for S	contracts02721/main.vl:12:5
  requires i >= 0 (trait)	contracts02721/main.vl:4:9
  requires j < self.n	contracts02721/main.vl:13:9
$ contracts declared contracts02721/main.vl
crate::declared	contracts02721/main.vl:20:8
  requires x > 0	contracts02721/main.vl:21:5
  ensures result > x	contracts02721/main.vl:22:5
$ items crate --undeclared contracts02721/main.vl
28	undeclared
undeclared: 1 of 2
