## 0.25.4: `volec fix --only unneeded-unsafe` (tests/refactor/unneeded0254/):
## the unsafe blocks `query unsafe` calls `none (unneeded)` taken away, the
## code in them kept and in its scope; (0.29) one it cannot open safely
## (it declares, and code follows) made a plain block, and one it leaves
## named with the reason. The program prints what it printed.
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
33 21
$ query unsafe main.vl
main.vl:5	extern	crate::extern	ffi	missing both	1 C function
main.vl:11	block	crate::add	other	missing both	none (unneeded)
main.vl:20	block	crate::two	other	missing both	none (unneeded)
main.vl:23	block	crate::two	other	missing both	none (unneeded)
main.vl:24	block	crate::two	other	missing both	none (unneeded)
main.vl:28	block	crate::two	other	missing both	none (unneeded)
main.vl:29	block	crate::two	other	missing both	none (unneeded)
main.vl:31	block	crate::two	other	missing both	none (unneeded)
main.vl:36	block	crate::two	ffi	missing both	c-call(strlen)
main.vl:37	block	crate::two	other	missing both	none (unneeded)
main.vl:43	block	crate::three	other	justified	none (unneeded)
main.vl:47	block	crate::three	other	missing both	none (unneeded)
main.vl:48	block	crate::three	other	missing both	none (unneeded)
main.vl:57	block	crate::main	other	missing both	none (unneeded)
main.vl:66	block	crate::bump	raw-pointer	justified	other
main.vl:74	block	crate::count	raw-pointer	justified	other
sites: 16 (15 blocks, 0 unsafe fns, 1 extern blocks); unjustified: 13; unneeded: 12
try: volec fix --only unneeded-unsafe
$ fix --only unneeded-unsafe --diff
fixed 10 unneeded unsafe blocks, 1 left as it is (query unsafe lists it)	main.vl	+13 -21 lines
--- a/main.vl
+++ b/main.vl
@@ -11,5 +11,3 @@
-    unsafe {
-        let y = x + 1;
-        bump(y);
-        y
-    }
+    let y = x + 1;
+    bump(y);
+    y
@@ -20,5 +18,3 @@
-    unsafe {
-        bump(1);
-    }
-    let c = unsafe { count() };
-    if unsafe { count() > 3 } {
+    bump(1);
+    let c = count();
+    if count() > 3 {
@@ -28,2 +24,2 @@
-    let d = 2 * unsafe { c + x };
-    unsafe { bump(d); }
+    let d = 2 * (c + x);
+    bump(d);
@@ -31 +27 @@
-    unsafe {
+    {
@@ -37 +33 @@
-    unsafe { if x > 0 { d } else { n } }
+    if x > 0 { d } else { n }
@@ -48,4 +44 @@
-        unsafe {
-            bump(2);
-        }
-        count()
+        bump(2);
@@ -52,0 +46 @@
+    count()
@@ -57,3 +51 @@
-    unsafe {
-        println("{s} {}", count());
-    }
+    println("{s} {}", count());
note fix.unneeded-left: main.vl:48: unsafe block left: it is inside a block taken away in this run: run it again
$ fix --only unneeded-unsafe
fixed 1 unneeded unsafe block	main.vl	+1 -3 lines
$ fix --only unneeded-unsafe
note fix.none: nothing to fix
% "$COMPILER" main.vl -o b >/dev/null 2>&1 && ./b
33 21
$ query unsafe main.vl
main.vl:5	extern	crate::extern	ffi	missing both	1 C function
main.vl:32	block	crate::two	ffi	missing both	c-call(strlen)
main.vl:39	block	crate::three	other	justified	none (unneeded)
main.vl:56	block	crate::bump	raw-pointer	justified	other
main.vl:64	block	crate::count	raw-pointer	justified	other
sites: 5 (4 blocks, 0 unsafe fns, 1 extern blocks); unjustified: 2; unneeded: 1
try: volec fix --only unneeded-justified
## (0.25.5) `--only unneeded-justified`: the justified one too, with the
## comments above it (they say why a block no longer needed was).
$ fix --only unneeded-justified --diff
fixed 1 unneeded unsafe block	main.vl	+1 -5 lines
--- a/main.vl
+++ b/main.vl
@@ -37,5 +37 @@
-    // UNSAFE: kept: its comments say why, a reader's to judge.
-    // SAFETY: nothing to it.
-    unsafe {
-        bump(1);
-    }
+    bump(1);
% "$COMPILER" main.vl -o c >/dev/null 2>&1 && ./c
33 21
$ query unsafe main.vl
main.vl:5	extern	crate::extern	ffi	missing both	1 C function
main.vl:32	block	crate::two	ffi	missing both	c-call(strlen)
main.vl:52	block	crate::bump	raw-pointer	justified	other
main.vl:60	block	crate::count	raw-pointer	justified	other
sites: 4 (3 blocks, 0 unsafe fns, 1 extern blocks); unjustified: 2; unneeded: 0
