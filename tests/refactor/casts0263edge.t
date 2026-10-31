## 0.26.3: `fix --only casts`, the edges of its rules
## (tests/refactor/casts0263edge/): a sign test written `0 <= n` stays; a
## comparison stays whole when one side stays; a let copied into a let,
## and a counter compared with such a let, go; a slicing to the end of a
## call's result, an inclusive slicing from an i64, and a generic
## function's cast (one per instance) stay. The program prints the same.
% volec main.vl -o before >/dev/null && ./before 2>&1
true true 118 3
3 true true
ok: built before
$ fix --only casts-list
main.vl:7	cmp-i64	cmp-i64	s.len as i64
main.vl:13	cmp-i64	cmp-i64	a.len as i64
main.vl:13	sub	sub	b.len as i64
main.vl:18	let	let	s.len as i64
main.vl:25	let	let	s.len as i64
main.vl:27	loop	loop	s.len as i64
main.vl:38	refused	index	std::trim(s).len as i64
main.vl:39	refused	index	a.len as i64
main.vl:40	arith	arith	b.len as i64
main.vl:45	copied	compare	v.len() as i64
main.vl:45	copied	compare	v.len() as i64
--- a/main.vl
+++ b/main.vl
@@ -18 +18 @@
-    let n = s.len as i64;
+    let n = s.len;
@@ -25 +25 @@
-    let n = s.len as i64;
+    let n = s.len;
@@ -27 +27 @@
-    for i in 0..s.len as i64 {
+    for i in 0..s.len {
note fix.casts: usize to i64 casts: removed index 0 slice-end 0 compare 0 loop 1 let 2; kept sub 1 arith 1 cmp-i64 2 stored 0 other 0 refused 2 copied 2; other casts to i64 noop 0 not-usize 0
$ fix --only casts
fixed 3 usize casts	main.vl	+3 -3 lines
note fix.casts: usize to i64 casts: removed index 0 slice-end 0 compare 0 loop 1 let 2; kept sub 1 arith 1 cmp-i64 2 stored 0 other 0 refused 2 copied 2; other casts to i64 noop 0 not-usize 0
% volec main.vl -o after >/dev/null && ./after 2>&1
true true 118 3
3 true true
ok: built after
