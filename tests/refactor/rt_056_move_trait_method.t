## XFAIL: RT-56: refactor move takes a method call to the module's other trait of that method name (meaning changed, the edit checks) (0.30.2)
## a::helper calls `t.val()` on an i64: in a, the trait in scope is
## a::T1 (val: +1). b has its own trait T2 with a `val` for i64 (* 1000).
## `refactor move crate::a::helper --to crate::b` fixes the paths of the
## items helper names, not the traits its method calls go through: the
## moved `t.val()` is T2's there, the program checks, and prints
## `5000 2000` instead of `6 2000`. The move must keep the call T1's
## (`T1::val(&t)`, with T1 imported) or refuse.
$ run
6 2000
$ refactor move crate::a::helper --to crate::b
error refactor.collision: the method call `t.val()` at a.vl:14:5 would call crate::b::T2's val in crate::b, not crate::a::T1's; nothing written
[exit 1]
$ run
6 2000
