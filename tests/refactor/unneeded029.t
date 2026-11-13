## 0.29: `volec fix --only unneeded-unsafe` (tests/refactor/unneeded029/):
## the blocks written over several lines (a function's whole body, a
## `let`'s value, an `if` or `while` condition, an operand), laid out as
## `volec fmt` would; a block that declares opened when the value of the
## block around it follows, else made a plain block; each block left with
## a note that says why. The program prints what it printed.
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
7 4 true
5
6
1
15 true 1
3
$ query unsafe main.vl --unneeded
main.vl:11	block	crate::cell_at	other	missing both	none (unneeded)
main.vl:15	block	crate::first_cells	other	missing both	none (unneeded)
main.vl:20	block	crate::row_sum_is	other	missing both	none (unneeded)
main.vl:36	block	crate::conditions	other	missing both	none (unneeded)
main.vl:44	block	crate::conditions	other	missing both	none (unneeded)
main.vl:51	block	crate::conditions	other	missing both	none (unneeded)
main.vl:59	block	crate::conditions	other	justified	none (unneeded)
main.vl:66	block	crate::conditions	other	justified	none (unneeded)
main.vl:66	block	crate::conditions	other	justified	none (unneeded)
main.vl:68	block	crate::conditions	other	missing both	none (unneeded)
main.vl:78	block	crate::find	other	missing both	none (unneeded)
main.vl:94	block	crate::shadowed	other	missing both	none (unneeded)
main.vl:98	block	crate::shadowed	other	missing both	none (unneeded)
main.vl:110	block	crate::kept	other	justified	none (unneeded)
main.vl:112	block	crate::kept	other	missing both	none (unneeded)
sites: 15 (15 blocks, 0 unsafe fns, 0 extern blocks); unjustified: 11; unneeded: 15
try: volec fix --only unneeded-unsafe
$ fix --only unneeded-unsafe --diff
fixed 10 unneeded unsafe blocks, 1 left as it is (query unsafe lists it)	main.vl	+21 -29 lines
--- a/main.vl
+++ b/main.vl
@@ -11,2 +11,2 @@
-fn cell_at(table: &Table<Gpa>, row: i64, column: i64) -> i64 { unsafe { (
-    table.cells[(row * table.width + column) as usize]) } }
+fn cell_at(table: &Table<Gpa>, row: i64, column: i64) -> i64 { (
+    table.cells[(row * table.width + column) as usize]) }
@@ -15,2 +15,2 @@
-    unsafe { &table.cells[
-        (0 * table.width) as usize..(rows_wanted * table.width + table.width - table.width) as usize] }
+    &table.cells[
+        (0 * table.width) as usize..(rows_wanted * table.width + table.width - table.width) as usize]
@@ -20 +20 @@
-    unsafe { same(
+    same(
@@ -23 +23 @@
-        wanted) }
+        wanted)
@@ -36,5 +36,3 @@
-    while unsafe {
-        open.len() as i64 > 0
-            && (open[(open.len() as i64 - 1) as usize])
-            != cell_at(table, 0, 1) + cell_at(table, 0, 0)
-    } {
+    while open.len() as i64 > 0
+        && (open[(open.len() as i64 - 1) as usize])
+        != cell_at(table, 0, 1) + cell_at(table, 0, 0) {
@@ -44,4 +42,2 @@
-    if unsafe {
-        cell_at(table, 0, 0) == 1 && cell_at(table, 0, 1) == 2 && cell_at(table, 0, 2) == 3
-            && cell_at(table, 0, 3) == 4 && row_sum_is(table, 0, 10)
-    } {
+    if cell_at(table, 0, 0) == 1 && cell_at(table, 0, 1) == 2 && cell_at(table, 0, 2) == 3
+        && cell_at(table, 0, 3) == 4 && row_sum_is(table, 0, 10) {
@@ -51,4 +47,2 @@
-    let corner = unsafe {
-        (table.cells[
-            ((table.cells.len() as i64 / table.width - 1) * table.width + table.width - 1) as usize])
-    };
+    let corner = (table.cells[
+        ((table.cells.len() as i64 / table.width - 1) * table.width + table.width - 1) as usize]);
@@ -68 +62 @@
-    let total = unsafe {
+    let total = {
@@ -78,7 +72,4 @@
-    unsafe {
-        let mut i: i64 = 0;
-        while i < table.cells.len() as i64 {
-            if (table.cells[i as usize]) == wanted {
-                return true;
-            }
-            i += 1;
+    let mut i: i64 = 0;
+    while i < table.cells.len() as i64 {
+        if (table.cells[i as usize]) == wanted {
+            return true;
@@ -85,0 +77 @@
+        i += 1;
@@ -94 +86 @@
-    unsafe {
+    {
@@ -98 +90 @@
-    unsafe {
+    {
note fix.unneeded-left: main.vl:112: unsafe block left: its code ends in a `//` comment, which would hold what follows the block
% volec fmt --check main.vl
$ fix --only unneeded-unsafe
note fix.unneeded-left: main.vl:104: unsafe block left: its code ends in a `//` comment, which would hold what follows the block
note fix.none: nothing to fix
$ query unsafe main.vl
main.vl:53	block	crate::conditions	other	justified	none (unneeded)
main.vl:60	block	crate::conditions	other	justified	none (unneeded)
main.vl:60	block	crate::conditions	other	justified	none (unneeded)
main.vl:102	block	crate::kept	other	justified	none (unneeded)
main.vl:102	block	crate::kept	raw-pointer	justified	deref
main.vl:104	block	crate::kept	other	missing both	none (unneeded)
sites: 6 (6 blocks, 0 unsafe fns, 0 extern blocks); unjustified: 1; unneeded: 5
try: volec fix --only unneeded-unsafe
## `--only unneeded-justified`: the comments above the statement go with
## its blocks, once for two blocks under them; they stay when another
## unsafe of the statement does.
$ fix --only unneeded-justified --diff
fixed 3 unneeded unsafe blocks, 2 left as they are (query unsafe lists them)	main.vl	+3 -7 lines
--- a/main.vl
+++ b/main.vl
@@ -50,2 +49,0 @@
-    // UNSAFE: the table was a raw one; every read was.
-    // SAFETY: two cells at least before the second from the end is read.
@@ -53,2 +51,2 @@
-        && unsafe { (open[(open.len() as i64 - 2) as usize]) }
-    >= corner + cell_at(table, 0, 0) + cell_at(table, 0, 1) + cell_at(table, 0, 2) + 100 {
+        && (open[(open.len() as i64 - 2) as usize])
+        >= corner + cell_at(table, 0, 0) + cell_at(table, 0, 1) + cell_at(table, 0, 2) + 100 {
@@ -58,3 +56 @@
-    // UNSAFE: a raw pointer was given to both calls.
-    // SAFETY: it pointed to the table for both.
-    let both = cell_at(unsafe { &*table }, 1, 1) == cell_at(unsafe { &*table }, 1, 1);
+    let both = cell_at(&*table, 1, 1) == cell_at(&*table, 1, 1);
note fix.unneeded-left: main.vl:102: unsafe block left: the comments above justify another unsafe of its statement, which stays
note fix.unneeded-left: main.vl:104: unsafe block left: its code ends in a `//` comment, which would hold what follows the block
% volec fmt --check main.vl
% "$COMPILER" main.vl -o b >/dev/null 2>&1 && ./b
7 4 true
5
6
1
15 true 1
3
$ query unsafe main.vl --summary
sites: 3 (3 blocks, 0 unsafe fns, 0 extern blocks); unjustified: 1; unneeded: 2

class	sites	unjustified
other	2	1
raw-pointer	1	0

module	sites	unjustified
crate	3	1

file	sites	unjustified
main.vl	3	1

justification	sites	unjustified
justified	2	0
missing both	1	1
try: volec fix --only unneeded-unsafe
$ explain fix.unneeded-left
fix.unneeded-left: note
(0.29) `fix --only unneeded-unsafe` (or `unneeded-justified`) left an unsafe block with nothing unsafe inside as it is, and says why: it is inside a block taken away in the same run; its file is generated; its code, an expression, holds a string or a comment written over several lines, or ends in a `//` comment; the comments above it justify another unsafe of its statement, which stays, or are not on the lines above its statement.
fix: Run it again for a block inside another; else take the block away by hand (its code holds nothing unsafe: the word `unsafe` and its braces go, or the word alone).
example:
    note fix.unneeded-left: main.vl:104: unsafe block left: its code ends in a `//` comment, which would hold what follows the block
