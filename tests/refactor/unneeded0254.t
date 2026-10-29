## 0.25.4: `volec fix --only unneeded-unsafe` (tests/refactor/unneeded0254/):
## the unsafe blocks `query unsafe` calls `none (unneeded)` taken away, the
## code in them kept and in its scope; those it cannot open safely left
## and counted. The program prints what it printed.
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
sites: 14 (13 blocks, 0 unsafe fns, 1 extern blocks); unjustified: 13; unneeded: 12
$ fix --only unneeded-unsafe --diff
fixed 9 unneeded unsafe blocks, 2 left as they are (query unsafe lists them)	main.vl	+12 -20 lines
--- a/main.vl
+++ b/main.vl
@@ -11,5 +11,3 @@
-    unsafe {
-        let y = x + 1;
-        COUNT += y;
-        y
-    }
+    let y = x + 1;
+    COUNT += y;
+    y
@@ -20,5 +18,3 @@
-    unsafe {
-        COUNT += 1;
-    }
-    let c = unsafe { COUNT };
-    if unsafe { COUNT > 3 } {
+    COUNT += 1;
+    let c = COUNT;
+    if COUNT > 3 {
@@ -28,2 +24,2 @@
-    let d = 2 * unsafe { c + x };
-    unsafe { COUNT += d; }
+    let d = 2 * (c + x);
+    COUNT += d;
@@ -37 +33 @@
-    unsafe { if x > 0 { d } else { n } }
+    if x > 0 { d } else { n }
@@ -48,4 +44 @@
-        unsafe {
-            COUNT += 2;
-        }
-        COUNT
+        COUNT += 2;
@@ -52,0 +46 @@
+    COUNT
@@ -57,3 +51 @@
-    unsafe {
-        println(f"{s} {COUNT}");
-    }
+    println(f"{s} {COUNT}");
$ fix --only unneeded-unsafe
fixed 1 unneeded unsafe block, 1 left as it is (query unsafe lists it)	main.vl	+1 -3 lines
$ fix --only unneeded-unsafe
note fix.none: nothing to fix
% "$COMPILER" main.vl -o b >/dev/null 2>&1 && ./b
33 21
$ query unsafe main.vl
main.vl:5	extern	crate::extern	ffi	missing both	1 C function
main.vl:27	block	crate::two	other	missing both	none (unneeded)
main.vl:32	block	crate::two	ffi	missing both	c-call(strlen)
main.vl:39	block	crate::three	other	justified	none (unneeded)
sites: 4 (3 blocks, 0 unsafe fns, 1 extern blocks); unjustified: 3; unneeded: 2
## (0.25.5) `--only unneeded-justified`: the justified one too, with the
## comments above it (they say why a block no longer needed was).
$ fix --only unneeded-justified --diff
fixed 1 unneeded unsafe block, 1 left as it is (query unsafe lists it)	main.vl	+1 -5 lines
--- a/main.vl
+++ b/main.vl
@@ -37,5 +37 @@
-    // UNSAFE: kept: its comments say why, a reader's to judge.
-    // SAFETY: nothing to it.
-    unsafe {
-        COUNT += 1;
-    }
+    COUNT += 1;
% "$COMPILER" main.vl -o c >/dev/null 2>&1 && ./c
33 21
$ query unsafe main.vl
main.vl:5	extern	crate::extern	ffi	missing both	1 C function
main.vl:27	block	crate::two	other	missing both	none (unneeded)
main.vl:32	block	crate::two	ffi	missing both	c-call(strlen)
sites: 3 (2 blocks, 0 unsafe fns, 1 extern blocks); unjustified: 3; unneeded: 1
