## volec rewrite on a program with errors, 0.30
## (tests/refactor/rewriteerr030/): 55 errors, more than a check reports.
% volec check main.vl 2>&1 | tail -2
main.vl:81:20: error[type error] no method 'nope49' on type 'Map' | try: volec query items Map main.vl
error: 5 more errors not shown (5 lines); --max-errors=0: all of them
% volec check --max-errors=0 main.vl 2>&1 | grep -v nope
main.vl:88:42: error[type error] expected 'i64', got 'Option<&i64>'
main.vl:89:13: error[type error] no method 'get' on type 'i64'
main.vl:90:18: error[type error] no method 'get' on type 'Option<&i64>' | help: no method of that name; the nearest: 'get_or_insert', 'get_or_insert_with' | try: volec query items Option main.vl
## The checker stopped at its 50th error and gave the code after it no
## types, so a typed rewrite found nothing there. A rewrite now checks
## the whole program: --where holds after the 50th error too.
$ rewrite '$v.get($i)' --list --where '$v: [i64; 4]'
main.vl:88:42	$v=cx.regs	$i=2	let a = cx.uses.get(1) + cx.head.get(cx.regs.get(2));
main.vl:90:18	$v=cx.regs	$i=1	let w: i64 = cx.regs.get(1).get(0);
note rewrite.types: 5 sites match but for --where; first: $v is IntVec at main.vl:88:13
try: volec rewrite '$v.get($i)' --where '$v: IntVec' --list
$ rewrite '$v.get($i)' --list --where '$v: Map'
main.vl:88:30	$v=cx.head	$i=cx.regs.get(2)	let a = cx.uses.get(1) + cx.head.get(cx.regs.get(2));
main.vl:89:13	$v=cx.head	$i=1	let z = cx.head.get(1).get(2);
note rewrite.types: 5 sites match but for --where; first: $v is IntVec at main.vl:88:13
try: volec rewrite '$v.get($i)' --where '$v: IntVec' --list
## --at-errors TEXT: only the sites where a current error with TEXT (its
## code, words of its message) is, whatever their types. The error is the
## site's own, not one in the code a hole matched.
$ rewrite '$v.get($i)' --list --at-errors "expected 'i64', got 'Option"
main.vl:88:42	$v=cx.regs	$i=2	let a = cx.uses.get(1) + cx.head.get(cx.regs.get(2));
note rewrite.at-errors: 6 sites match where no such error is: left
$ rewrite '$v.get($i)' '$v[$i]' --at-errors "expected 'i64', got 'Option" --dry-run
--- a/main.vl
+++ b/main.vl
@@ -88 +88 @@
-    let a = cx.uses.get(1) + cx.head.get(cx.regs.get(2));
+    let a = cx.uses.get(1) + cx.head.get(cx.regs[2]);
note rewrite.at-errors: 6 sites match where no such error is: left
## An error has a position and no extent: of `m.get(1).get(2)` the second
## `get` is the unknown one, the call the checker gave no type.
$ rewrite '$v.get($i)' --list --at-errors "no method 'get'"
main.vl:89:13	$v=cx.head.get(1)	$i=2	let z = cx.head.get(1).get(2);
main.vl:90:18	$v=cx.regs.get(1)	$i=0	let w: i64 = cx.regs.get(1).get(0);
note rewrite.at-errors: 5 sites match where no such error is: left
$ rewrite '$v.$m($a...)' --list --at-errors 'no method' --in total
main.vl:89:13	$v=cx.head.get(1)	$m=get	$a...=2	let z = cx.head.get(1).get(2);
main.vl:90:18	$v=cx.regs.get(1)	$m=get	$a...=0	let w: i64 = cx.regs.get(1).get(0);
note rewrite.at-errors: 5 sites match where no such error is: left
% volec rewrite '$v.$m()' --list --at-errors 'no method' main.vl | wc -l | tr -d ' '
52
$ rewrite '$v.get($i)' --list --at-errors 'nothing like it'
note rewrite.at-errors: no error of the program has 'nothing like it' (55 errors: their lines are `volec check`'s, `FILE:L:C: error[CODE] MESSAGE`); nothing to rewrite
## Written: the errors it fixed are gone, the rest are as they were.
$ rewrite '$v.get($i)' '$v[$i]' --at-errors "expected 'i64', got 'Option"
rewrote 1 site in 1 file	main.vl	+1 -1 lines
note rewrite.at-errors: 6 sites match where no such error is: left
% volec check --max-errors=0 main.vl 2>&1 | grep -v nope
main.vl:89:13: error[type error] no method 'get' on type 'i64'
main.vl:90:18: error[type error] no method 'get' on type 'Option<&i64>' | help: no method of that name; the nearest: 'get_or_insert', 'get_or_insert_with' | try: volec query items Option main.vl
