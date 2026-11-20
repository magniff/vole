## XFAIL: RT-66: refactor inline puts a moved argument of a type with a Drop impl in for the parameter: its drop moves to the caller's scope end (0.30.2)
## f(d: D) drops its D when it returns: `in f`, `drop 1`, `after 1`.
## `refactor inline f` writes `let r = { println("in f"); d.k };`: d is
## no longer moved, it is dropped at the end of main, and the program
## checks and prints `in f`, `after 1`, `drop 1`. The parameter must be
## bound in the block (`let d = d;`), as inline does for an argument it
## evaluates, when its type has drop glue.
$ run
in f
drop 1
after 1
$ refactor inline f
inlined crate::f at 1 call, deleted it	main.vl	+5 -6 lines
$ run
in f
drop 1
after 1
