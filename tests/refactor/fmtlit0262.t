## 0.26.2: the tools in format literals: a rename of a local, of a
## width's `name$` and of a const rewrites the names in the literal's
## holes, and leaves a plain literal that is no format string alone;
## volec fmt keeps a format literal's bytes.
$ fmt --dry-run
--- a/main.vl
+++ b/main.vl
@@ -7 +7 @@
-    println( "{}  {{x}}" ,count );
+    println("{}  {{x}}", count);
$ refactor rename main.vl:4:9 n
renamed local count to n in crate::main, 3 uses	main.vl	+3 -3 lines
$ refactor rename main.vl:5:9 w
renamed local width to w in crate::main, 1 use	main.vl	+2 -2 lines
$ refactor rename LIMIT CAP
renamed crate::LIMIT to CAP	main.vl	+2 -2 lines
% cat main.vl
const CAP: i64 = 9;

fn main() {
    let n = 3;
    let w = 6;
    println("{n} items, {n:>w$} of {CAP}");
    println("{}  {{x}}", n);
    let s = "{count} stays text";
    println(s);
}
