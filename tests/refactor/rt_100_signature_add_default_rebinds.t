## XFAIL: RT-100: refactor signature --add writes the default's text at every call, where its names resolve in the call's scope: another module's K, a local closure named like the fn (0.30.2)
## `--add 'k: i64 = K'`, run on crate::scale with crate::K = 100, writes
## `crate::scale(10, K)` in a.vl, where K is a's own const (7); `--add
## 'k: i64 = base()'` on shift writes `shift(2, base())` after `let base =
## || 5;` in main, which calls the closure, not crate::base (1000). Each
## answers only `added parameter ...` and the program checks. Once the
## body uses k (the reason to add it), a::other() is 27 instead of 120 and
## shift(2) is 8 instead of 1003. The default must mean what it means
## where the function is defined: its names qualified at each call
## (`crate::K`, `crate::base()`), or the edit refused (a refactor.collision
## like move's), as RT-TL-11 asks of inline.
$ refactor signature scale --add 'k: i64 = K'
added parameter k: i64 to crate::scale, 2 calls	2 files	+3 -3 lines
% grep -n 'scale(' main.vl a.vl
main.vl:9:fn scale(x: i64, k: i64) -> i64 {
main.vl:18:    println("{}", scale(1, crate::K));
a.vl:4:    crate::scale(10, crate::K)
$ refactor signature shift --add 'k: i64 = base()'
added parameter k: i64 to crate::shift, 1 call	main.vl	+2 -2 lines
% grep -n 'shift(' main.vl
13:fn shift(x: i64, k: i64) -> i64 {
21:    println("{} {}", shift(2, crate::base()), base());
