## (0.29) `*const T` and `*mut T` are two types (F30.5): a `*const T`
## where a `*mut T` is expected is an error whose help names the cast
## and, when the value is checked against a written type, where that
## `*mut` is declared; `fix --suggested` writes the cast at every one
## in one checked edit. `query type` prints the two pointers as they are
## written.
$ check
main.vl:12:10: error[type error] expected '*mut i64', got '*const i64' | help: the types differ in mutability (rustc E0308): a `*const T` does not convert to a `*mut T`; cast it, if what it points to may be written through it, or write `*const` where the `*mut` is declared, at main.vl:1:12 | try: c as *mut i64 | try: volec fix --suggested main.vl
main.vl:13:34: error[type error] expected '*mut i64', got '*const i64' | help: the types differ in mutability (rustc E0308): a `*const T` does not convert to a `*mut T`; cast it, if what it points to may be written through it | try: c as *mut i64 | try: volec fix --suggested main.vl
[exit 1]
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -12,2 +12,2 @@
-    bump(c);
-    let m: *mut i64 = if x > 0 { c } else { c };
+    bump(c as *mut i64);
+    let m: *mut i64 = if x > 0 { c as *mut i64 } else { c as *mut i64 };
$ fix --suggested
fixed 3 suggested fixes	main.vl	+2 -2 lines
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
$ query type main.vl:11:9
*const i64	c
$ query type main.vl:13:9
*mut i64	m
% volec main.vl -o prog >/dev/null && ./prog
43 true
ok: built prog
