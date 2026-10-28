## 0.25.2 diagnostics and tools (tests/refactor/diag252/).
## An import nothing in its file names: a warning, use.unused, its try:
## removing it.
$ check
main.vl:5:20: warning[use.unused] unused import 'perimeter': nothing in this file names it | help: remove it (`volec fix` removes every unused import) | try: volec fix --only unused main.vl
ok: 0 errors, 1 warning in main.vl
## volec fix (and --only unused) removes it.
$ fix --only unused
fixed 1 unused import	main.vl	+1 -1 lines
% git diff --stat
 main.vl | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
## A hunk of several lines given at another indentation (as copied from
## `query show` of a nested block): matched as with --loose, NEW
## re-indented, a note.
$ edit patch main < $T/inputs/diag252_nested.patch
patched crate::main	main.vl	+1 -0 lines
note patch.loose: OLD 1 matched with other indentation at line 10; NEW re-indented like it (--loose)
% git diff main.vl
diff --git a/main.vl b/main.vl
index 4d2a85a..9a7a43b 100644
--- a/main.vl
+++ b/main.vl
@@ -2,12 +2,13 @@
 
 mod shapes;
 
-use shapes::{area, perimeter};
+use shapes::area;
 
 fn main() -> i32 {
     let a = area(2, 3);
     if a > 5 {
         if a < 10 {
+            // small
             return 0;
         }
     }
## fmt --changed: the .vl files changed since HEAD only.
% printf 'pub fn area(w: i64, h: i64) -> i64 {\n      w * h\n}\n\npub fn perimeter(w: i64, h: i64) -> i64 {\n    2 * (w + h)\n}\n' > shapes.vl
$ fmt --changed --check
shapes.vl
error fmt.unformatted: 1 of 2 files are not formatted
try: volec fmt --dry-run shapes.vl
try: volec fmt shapes.vl
[exit 1]
$ fmt --since nosuchrev
error fmt.no-git: git cannot tell which files changed since nosuchrev: no checkout here, or no such revision
[exit 1]
$ fmt --changed
formatted	shapes.vl	+1 -1 lines
$ fmt --since HEAD --check
