## volec fix --suggested (0.18; tests/refactor/suggested/): an error
## whose fix the compiler knows exactly prints `try: volec fix
## --suggested ROOT`; the command makes every such fix as one checked
## edit, the imports and pubs too, then prints the errors left. One of
## each kind: a did-you-mean (a variable, a method) with one name that
## near, a conversion (`as`, `!= 0`), the `_in` form with this
## function's `gpa`, a missing `gpa` argument, a missing `use` (std's,
## the crate's: a function, a type), a missing `pub`, a module path from
## `crate::` (a value, a type, a `use` line); a tie (`cut`: `cat` and
## `cot`) is left, and an `as` that would wrap is refused.
$ check
main.vl:22:13: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
main.vl:24:21: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: total(&v) as u8
main.vl:25:8: error[type error] expected 'bool', got 'i64' | help: a condition is a bool: compare (`x != 0`); bitwise not is `~x` | try: n != 0 | try: volec fix --suggested main.vl
main.vl:28:21: error[type error] expected 'f64', got 'i64' | help: only widening is implicit: convert explicitly | try: n as f64 | try: volec fix --suggested main.vl
main.vl:30:13: error[alloc.no_in] 'String::from' allocates from nothing: pass the allocator, last, to 'String::from_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:31:25: error[type error] unknown type 'Rect' | help: add `use crate::lib::shapes::Rect;` | try: volec fix --suggested main.vl
main.vl:32:13: error[item.private] 'describe' is private | help: make it public: `pub fn describe` at text.vl:3:1 | try: volec fix --suggested main.vl
main.vl:33:13: error[type error] function 'table::make' expects 2 arguments, got 1 | help: its signature: `fn make(width: i64, gpa: Gpa) -> Table<Gpa>` (table.vl:5) | try: table::make(3, gpa) | try: volec fix --suggested main.vl
main.vl:35:5: error[type error] no method 'push_string' on type 'String<Gpa>' | help: did you mean 'push_str'? | try: volec query items String main.vl | try: volec fix --suggested main.vl
main.vl:38:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
text.vl:1:5: error[type error] unknown module 'inner' | help: 'inner' is the module crate::lib::inner; a path starts in this module, beside it or at the root: write `crate::lib::inner::...` | try: use crate::lib::inner::width; | try: volec fix --suggested main.vl
text.vl:4:12: error[type error] unknown module 'shapes' | help: 'shapes' is the module crate::lib::shapes; a path starts in this module, beside it or at the root: write `crate::lib::shapes::...` | try: use crate::lib::shapes; | try: volec fix --suggested main.vl
text.vl:5:5: error[type error] unknown module 'shapes' | help: 'shapes' is the module crate::lib::shapes; a path starts in this module, beside it or at the root: write `crate::lib::shapes::...` | try: use crate::lib::shapes; | try: volec fix --suggested main.vl
text.vl:9:19: error[type error] unknown type 'HashMap' | help: add `use std::collections::HashMap;` | try: volec fix --suggested main.vl
[exit 1]
## The diff first; one line's fixes; one file's.
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -0,0 +1,3 @@
+use crate::lib::shapes::Rect;
+use crate::text::wrap;
+
@@ -22 +25 @@
-    let t = totl(&v);
+    let t = total(&v);
@@ -25 +28 @@
-    if n {
+    if n != 0 {
@@ -28 +31 @@
-    let wide: f64 = n;
+    let wide: f64 = n as f64;
@@ -30 +33 @@
-    let w = String::from(s);
+    let w = String::from_in(s, gpa);
@@ -33 +36 @@
-    let r = table::make(3);
+    let r = table::make(3, gpa);
@@ -35 +38 @@
-    b.push_string(wrap(s));
+    b.push_str(wrap(s));
--- a/text.vl
+++ b/text.vl
@@ -1 +1 @@
-use inner::width;
+use std::collections::HashMap;
@@ -3,3 +3,5 @@
-fn describe(n: i64) -> i64 {
-    let r: shapes::Rect = shapes::Rect { w: n, h: 2 };
-    shapes::area(r)
+use crate::lib::inner::width;
+
+pub fn describe(n: i64) -> i64 {
+    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
+    crate::lib::shapes::area(r)
note fix.refused: main.vl:24:21: not applied: `total(&v) as u8`: the integer type it goes to does not hold every value: it wraps
$ fix --suggested --at main.vl:25 --dry-run
--- a/main.vl
+++ b/main.vl
@@ -25 +25 @@
-    if n {
+    if n != 0 {
$ fix --suggested --in text.vl --dry-run
--- a/text.vl
+++ b/text.vl
@@ -1 +1 @@
-use inner::width;
+use std::collections::HashMap;
@@ -3,3 +3,5 @@
-fn describe(n: i64) -> i64 {
-    let r: shapes::Rect = shapes::Rect { w: n, h: 2 };
-    shapes::area(r)
+use crate::lib::inner::width;
+
+pub fn describe(n: i64) -> i64 {
+    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
+    crate::lib::shapes::area(r)
$ fix --suggested --show
fixed 3 missing imports, 1 pub, 10 suggested fixes	2 files	+15 -10 lines
// main.vl:1-3
1	use crate::lib::shapes::Rect;
2	use crate::text::wrap;
3	
// main.vl:25
25	    let t = total(&v);
// main.vl:28
28	    if n != 0 {
// main.vl:31
31	    let wide: f64 = n as f64;
// main.vl:33
33	    let w = String::from_in(s, gpa);
// main.vl:36
36	    let r = table::make(3, gpa);
// main.vl:38
38	    b.push_str(wrap(s));
// text.vl:1
1	use std::collections::HashMap;
// text.vl:3-7
3	use crate::lib::inner::width;
4	
5	pub fn describe(n: i64) -> i64 {
6	    let r: crate::lib::shapes::Rect = crate::lib::shapes::Rect { w: n, h: 2 };
7	    crate::lib::shapes::area(r)
main.vl:27:21: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: total(&v) as u8
main.vl:41:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
note fix.refused: main.vl:24:21: not applied: `total(&v) as u8`: the integer type it goes to does not hold every value: it wraps
note fix.left: 2 errors left (above)
$ check
main.vl:27:21: error[type error] expected 'u8', got 'i64' | help: only widening is implicit: convert explicitly | try: total(&v) as u8
main.vl:41:16: error[type error] undefined variable 'cut' | help: did you mean 'cat'?
[exit 1]
$ undo
undid fixed 3 missing imports, 1 pub, 10 suggested fixes	2 files	+15 -10 lines
## A fix that makes an error on its own line refuses the edit.
$ fix --suggested refuse.vl
note fix.refused: refuse.vl:5:18: not applied: `length`: the edited program has a new error with it: refuse.vl:5:18: error[type error] expected 'i64', got '&str'
note fix.none: nothing to fix: every fix was refused (above)
[exit 1]
## --at is for --suggested.
$ fix --at main.vl:25
error fix.usage: --at is for --suggested: the fixes of the errors at a line
[exit 2]
$ fix --suggested --at main.vl
error fix.usage: --at takes FILE:LINE, the line of an error
[exit 2]
