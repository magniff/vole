## 0.26.4: `fix --only rawptr` (tests/refactor/rawptr0264/): the raw
## pointer parameters decided. Written through, or a plain value a let
## would copy, to inout, the calls given `&cx`, `(*cx).m` to `cx.m`; a
## stored one, an indexed one, a C string stay raw; a call inside another
## call's arguments that takes the same context is taken into a let first
## (0.27.0, a run of its own: tests/refactor/rawptr0270.t); a raw pointer
## given becomes `&*q` (outside unsafe code, in a new block with its
## UNSAFE:/SAFETY: comments). The first run takes the nested call into a
## let, the second decides; a third changes nothing, and the program
## prints the same.
% volec main.vl -o before >/dev/null && ./before 2>&1
11 12 12 6 118
ok: built before
$ fix --only rawptr-list
main.vl:13	caller	raw-arg	total	cx: sink *Ctx	big	from_raw
main.vl:18	caller	raw-arg	bump	cx: sink *Ctx	big	from_raw
main.vl:26	escape	stored	keep	cx: *Ctx	big
main.vl:31	write	-	bump_and_keep	cx: *Ctx	big
main.vl:37	escape	indexed	sum	p: *i64	copy
main.vl:46	escape	indexed	first	s: *u8	u8
main.vl:52	write	-	nested	cx: *Ctx	big
--- a/main.vl
+++ b/main.vl
@@ -53 +53,2 @@
-    bump(cx, total(cx));
+    let total_v = total(cx);
+    bump(cx, total_v);
note fix.rawptr: raw pointer parameters: read 0 write 2 escape 3 caller 2 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 2 owned 0; reasons stored 1 returned 0 cast 0 compared 0 indexed 2 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 2 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 0; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 3; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 1
$ fix --only rawptr
fixed 1 nested call taken into a let (run it again)	main.vl	+2 -1 lines
note fix.rawptr: raw pointer parameters: read 0 write 2 escape 3 caller 2 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 2 owned 0; reasons stored 1 returned 0 cast 0 compared 0 indexed 2 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 2 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 0; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 3; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 1
% volec main.vl -o after >/dev/null && ./after 2>&1
11 12 12 6 118
ok: built after
$ fix --only rawptr
fixed 4 raw pointer parameters	main.vl	+16 -12 lines
note fix.rawptr: raw pointer parameters: read 0 write 2 escape 3 caller 2 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 2 owned 0; reasons stored 1 returned 0 cast 0 compared 0 indexed 2 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 2 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 0; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 3; edits: to inout 4, to let 0, `&p` 5, `&x` to `x` 0, `*p` to `p` 1, `&*q` 3 (in a new unsafe block 2); nested calls taken into lets 0
% volec main.vl -o last >/dev/null && ./last 2>&1
11 12 12 6 118
ok: built last
$ fix --only rawptr
note fix.rawptr: raw pointer parameters: read 0 write 0 escape 3 caller 0 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 0 owned 0; reasons stored 1 returned 0 cast 0 compared 0 indexed 2 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 0 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 0; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 0; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 0
note fix.none: nothing to fix
