## volec fix --suggested (0.18; tests/refactor/suggested/): an error
## whose fix the compiler knows exactly prints `try: volec fix
## --suggested ROOT`; the command makes every such fix as one checked
## edit, the imports and pubs too, then prints the errors left. One of
## each kind: a did-you-mean (a variable, a method) with one name that
## near, a conversion (`as`, `!= 0`, `[..]`), std's function for a method,
## the `_in` form with this function's `gpa`, a missing `gpa` argument, a
## missing `use` (std's, the crate's), a missing `pub`, a module path from
## `crate::` (a value, a type, a `use` line), Rust's types (`&str`,
## `String`, `char`); a tie (`cut`: `cat` and `cot`) is left.
$ check
main.vl:7:13: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:20:12: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:22:13: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
main.vl:25:8: error[type error] expected 'bool', got 'i64' | help: a condition is a bool: compare (`x != 0`); bitwise not is `~x` | try: n != 0 | try: volec fix --suggested main.vl
main.vl:29:13: error[alloc.no_in] 'format' allocates from nothing: pass the allocator, last, to 'format_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc main.vl
main.vl:30:15: error[type error] undefined variable 'I64_MIN' | help: add `use std::I64_MIN;` | try: volec fix --suggested main.vl
main.vl:31:13: error[item.private] 'describe' is private | help: make it public: `pub fn describe` at text.vl:3:1 | try: volec fix --suggested main.vl
main.vl:32:13: error[type error] function 'table::make' expects 2 arguments, got 1 | help: its signature: `fn make(width: i64, gpa: Gpa) -> Table` (table.vl:3) | try: table::make(3, gpa) | try: volec fix --suggested main.vl
main.vl:34:5: error[type error] no method 'push_string' on type 'Buf<Gpa>' | help: did you mean 'push_str'? | try: volec query items Buf main.vl | try: volec fix --suggested main.vl
main.vl:37:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
table.vl:1:46: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
text.vl:1:5: error[type error] unknown module 'inner' | help: 'inner' is the module crate::lib::inner; a path starts in this module, beside it or at the root: write `crate::lib::inner::...` | try: use crate::lib::inner::width; | try: volec fix --suggested main.vl
text.vl:4:12: error[type error] unknown module 'shapes' | help: 'shapes' is the module crate::lib::shapes; a path starts in this module, beside it or at the root: write `crate::lib::shapes::...` | try: use crate::lib::shapes; | try: volec fix --suggested main.vl
text.vl:5:5: error[type error] unknown module 'shapes' | help: 'shapes' is the module crate::lib::shapes; a path starts in this module, beside it or at the root: write `crate::lib::shapes::...` | try: use crate::lib::shapes; | try: volec fix --suggested main.vl
text.vl:9:12: error[type error] unknown type 'char' | help: `u8`: text is bytes, and 'a' is a u8 | try: u8 | try: volec fix --suggested main.vl
[exit 1]
## The diff first; one line's fixes; one file's.
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -0,0 +1,4 @@
+use std::I64_MIN;
+
+use text::wrap;
+
@@ -7 +11 @@
-fn total(v: Vec<i64>) -> i64 {
+fn total(v: Vec<i64, Gpa>) -> i64 {
@@ -20 +24 @@
-    var v: Vec<i64> = Vec::new_in(gpa);
+    var v: Vec<i64, Gpa> = Vec::new_in(gpa);
@@ -22 +26 @@
-    let t = totl(&v);
+    let t = total(v);
@@ -25 +29 @@
-    if n {
+    if n != 0 {
@@ -32 +36 @@
-    let r = table::make(3);
+    let r = table::make(3, gpa);
@@ -34 +38 @@
-    b.push_string(wrap(s));
+    b.push_str(wrap(s));
--- a/table.vl
+++ b/table.vl
@@ -1 +1 @@
-pub struct Table { pub width: i64, pub rows: Vec<i64> }
+pub struct Table { pub width: i64, pub rows: Vec<i64, Gpa> }
--- a/text.vl
+++ b/text.vl
@@ -1 +1 @@
-use inner::width;
+use crate::lib::inner::width;
@@ -3,3 +3,3 @@
-fn describe(n: i64) -> i64 {
-    let r: shapes::Rect = shapes::Rect { w: n, h: 2 };
-    shapes::area(&r)
+pub fn describe(n: i64) -> i64 {
+    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
+    crate::lib::shapes::area(r)
@@ -9 +9 @@
-    let c: char = 'x';
+    let c: u8 = 'x';
$ fix --suggested --at main.vl:23 --dry-run
note fix.none: nothing to fix
$ fix --suggested --in text.vl --dry-run
--- a/text.vl
+++ b/text.vl
@@ -1 +1 @@
-use inner::width;
+use crate::lib::inner::width;
@@ -3,3 +3,3 @@
-fn describe(n: i64) -> i64 {
-    let r: shapes::Rect = shapes::Rect { w: n, h: 2 };
-    shapes::area(&r)
+pub fn describe(n: i64) -> i64 {
+    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
+    crate::lib::shapes::area(r)
@@ -9 +9 @@
-    let c: char = 'x';
+    let c: u8 = 'x';
$ fix --suggested --show
fixed 2 missing imports, 1 pub, 14 suggested fixes	3 files	+16 -12 lines
// main.vl:1-4
1	use std::I64_MIN;
2	
3	use text::wrap;
4	
// main.vl:11
11	fn total(v: Vec<i64, Gpa>) -> i64 {
// main.vl:24
24	    var v: Vec<i64, Gpa> = Vec::new_in(gpa);
// main.vl:26
26	    let t = total(v);
// main.vl:29
29	    if n != 0 {
// main.vl:36
36	    let r = table::make(3, gpa);
// main.vl:38
38	    b.push_str(wrap(s));
// table.vl:1
1	pub struct Table { pub width: i64, pub rows: Vec<i64, Gpa> }
// text.vl:1
1	use crate::lib::inner::width;
// text.vl:3-5
3	pub fn describe(n: i64) -> i64 {
4	    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
5	    crate::lib::shapes::area(r)
// text.vl:9
9	    let c: u8 = 'x';
main.vl:27:21: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: t as u8
main.vl:33:13: error[alloc.no_in] 'format' allocates from nothing: pass the allocator, last, to 'format_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc main.vl
main.vl:41:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
note fix.left: 3 errors left (above)
$ check
main.vl:27:21: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: t as u8
main.vl:33:13: error[alloc.no_in] 'format' allocates from nothing: pass the allocator, last, to 'format_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc main.vl
main.vl:41:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
[exit 1]
$ undo
undid fixed 2 missing imports, 1 pub, 14 suggested fixes	3 files	+16 -12 lines
## A Rust label: the program does not lex; the fix respells each line.
$ fix --suggested labels.vl --show
fixed 3 suggested fixes	labels.vl	+3 -3 lines
// labels.vl:3-4
3	    var n = 0;
4	    outer: for i in 0..3 {
// labels.vl:7
7	                break :outer;
## A fix that makes an error on its own line refuses the edit.
$ fix --suggested refuse.vl
note fix.refused: refuse.vl:5:18: not applied: `length`: the edited program has a new error with it: refuse.vl:5:18: error[type error] expected 'i64', got '[u8]'
note fix.none: nothing to fix: every fix was refused (above)
[exit 1]
## --at is for --suggested.
$ fix --at main.vl:24
error fix.usage: --at is for --suggested: the fixes of the errors at a line
[exit 2]
$ fix --suggested --at main.vl
error fix.usage: --at takes FILE:LINE, the line of an error
[exit 2]
