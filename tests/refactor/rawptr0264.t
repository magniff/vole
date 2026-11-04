## 0.26.4: `fix --only rawptr` (tests/refactor/rawptr0264/): the raw
## pointer parameters decided. Written through, or a plain value a let
## would copy, to inout, the calls given `&cx`, `(*cx).m` to `cx.m`; a
## stored one, an indexed one, a C string stay raw; a call inside another
## call's arguments that takes the same context stays raw (own.conflict
## otherwise); a raw pointer given becomes `&*q` (outside unsafe code, in
## a new block with its UNSAFE:/SAFETY: comments). A second run changes
## nothing, and the program prints the same.
% volec main.vl -o before >/dev/null && ./before 2>&1
11 12 12 6 118
ok: built before
$ fix --only rawptr-list
main.vl:13	escape	nested-call	total	cx: sink *Ctx	big
main.vl:18	caller	raw-arg	bump	cx: sink *Ctx	big	from_raw
main.vl:26	escape	stored	keep	cx: *Ctx	big
main.vl:31	write	-	bump_and_keep	cx: *Ctx	big
main.vl:37	escape	indexed	sum	p: *i64	copy
main.vl:46	escape	indexed	first	s: *u8	u8
main.vl:52	write	-	nested	cx: *Ctx	big
--- a/main.vl
+++ b/main.vl
@@ -18 +18 @@
-fn bump(cx: sink *Ctx, by: i64) {
+fn bump(cx: inout Ctx, by: i64) {
@@ -21 +21 @@
-        (*cx).m = total(cx);
+        cx.m = total(&cx);
@@ -31,3 +31,3 @@
-fn bump_and_keep(cx: *Ctx) {
-    bump(cx, 1);
-    keep(cx);
+fn bump_and_keep(cx: inout Ctx) {
+    bump(&cx, 1);
+    keep(&cx);
@@ -52,2 +52,2 @@
-fn nested(cx: *Ctx) {
-    bump(cx, total(cx));
+fn nested(cx: inout Ctx) {
+    bump(&cx, total(&cx));
@@ -59 +59 @@
-    unsafe { bump(q, 2) };
+    unsafe { bump(&*q, 2) };
@@ -70 +70,3 @@
-    bump(KEPT, 0);
+    // UNSAFE: a raw pointer given to an inout parameter (fix --only rawptr).
+    // SAFETY: it points to one live value for the whole call, as the raw parameter took it.
+    bump(unsafe { &*KEPT }, 0);
note fix.rawptr: raw pointer parameters: read 0 write 2 escape 4 caller 1 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 2 owned 0; reasons stored 1 returned 0 cast 0 compared 0 indexed 2 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 1 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 1; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 2; edits: to inout 3, to let 0, `&p` 5, `&x` to `x` 0, `*p` to `p` 1, `&*q` 2 (in a new unsafe block 1)
$ fix --only rawptr
fixed 3 raw pointer parameters	main.vl	+11 -9 lines
note fix.rawptr: raw pointer parameters: read 0 write 2 escape 4 caller 1 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 2 owned 0; reasons stored 1 returned 0 cast 0 compared 0 indexed 2 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 1 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 1; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 2; edits: to inout 3, to let 0, `&p` 5, `&x` to `x` 0, `*p` to `p` 1, `&*q` 2 (in a new unsafe block 1)
% volec main.vl -o after >/dev/null && ./after 2>&1
11 12 12 6 118
ok: built after
$ fix --only rawptr
note fix.rawptr: raw pointer parameters: read 0 write 0 escape 4 caller 0 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 0 owned 0; reasons stored 1 returned 0 cast 0 compared 0 indexed 2 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 0 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 1; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 0; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0)
note fix.none: nothing to fix
