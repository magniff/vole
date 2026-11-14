## volec rewrite, 0.30 (tests/refactor/rewrite030/): the sites inside the
## function the replacement calls, --not-in.
$ check
ok: 0 errors in main.vl (2 files, 0 shaders)
## A replacement that lands inside the function it calls: the helper's own
## body would become a call of the helper. Refused, with the command that
## leaves the function out.
$ rewrite '$s.len() as i64 * 2' 'twice_len($s)'
error rewrite.recursive: 1 site is inside the function its replacement calls there (the function would call itself); first: tab.vl:57:5 in tab::twice_len; nothing written
try: volec rewrite '$s.len() as i64 * 2' 'twice_len($s)' --not-in tab::twice_len
try: volec rewrite '$s.len() as i64 * 2' 'twice_len($s)' --force
[exit 1]
$ rewrite '$s.len() as i64 * 2' 'twice_len($s)' --not-in twice_len --dry-run
--- a/main.vl
+++ b/main.vl
@@ -13 +13 @@
-    let n = twice_len(b"vole") + b"abc".len() as i64 * 2;
+    let n = twice_len(b"vole") + twice_len(b"abc");
## An operator's function: `$t[$i]` in the Index impl of $t's type is
## `index` calling itself; `&mut $t[$i]` in IndexMut's.
$ rewrite '$t.get($i)' '&$t[$i]' --dry-run
error rewrite.recursive: 1 site is inside the function its replacement calls there (the function would call itself); first: tab.vl:33:9 in <tab::Tab as Index>::index; nothing written
try: volec rewrite '$t.get($i)' '&$t[$i]' --dry-run --not-in tab.vl:33
try: volec rewrite '$t.get($i)' '&$t[$i]' --dry-run --force
[exit 1]
$ rewrite '&mut $t.rows[$i]' '&mut $t[$i]' --dry-run
error rewrite.recursive: 1 site is inside the function its replacement calls there (the function would call itself); first: tab.vl:39:9 in <tab::Tab as IndexMut>::index_mut; nothing written
try: volec rewrite '&mut $t.rows[$i]' '&mut $t[$i]' --dry-run --not-in tab.vl:39
try: volec rewrite '&mut $t.rows[$i]' '&mut $t[$i]' --dry-run --force
[exit 1]
## (`&mut e` in a pattern is not `&e`)
$ rewrite '&$t.rows[$i]' '&$t[$i]' --list
tab.vl:25:9	$t=self	$i=i
## A method of the receiver's own type; a path to it.
$ rewrite '&$t.rows[$i]' '$t.get($i)' --dry-run
error rewrite.recursive: 1 site is inside the function its replacement calls there (the function would call itself); first: tab.vl:25:9 in tab::Tab::get; nothing written
try: volec rewrite '&$t.rows[$i]' '$t.get($i)' --dry-run --not-in tab::Tab::get
try: volec rewrite '&$t.rows[$i]' '$t.get($i)' --dry-run --force
[exit 1]
$ rewrite '&$t.rows[$i]' 'Tab::get($t, $i)' --dry-run
error rewrite.recursive: 1 site is inside the function its replacement calls there (the function would call itself); first: tab.vl:25:9 in tab::Tab::get; nothing written
try: volec rewrite '&$t.rows[$i]' 'Tab::get($t, $i)' --dry-run --not-in tab::Tab::get
try: volec rewrite '&$t.rows[$i]' 'Tab::get($t, $i)' --dry-run --force
[exit 1]
## A callee the pattern has too is not new at the site.
$ rewrite '$t.get($i)' '$t.get($i + 0)' --in at --dry-run
--- a/tab.vl
+++ b/tab.vl
@@ -44 +44 @@
-    *t.get(i)
+    *t.get(i + 0)
## --force writes it; --not-in a file, an item (repeated), FILE:LINE.
$ rewrite '$t.get($i)' '&$t[$i]' --force --dry-run
--- a/tab.vl
+++ b/tab.vl
@@ -33 +33 @@
-        self.get(i)
+        &self[i]
@@ -44 +44 @@
-    *t.get(i)
+    *&t[i]
@@ -48 +48 @@
-    *t.get(i)
+    *&t[i]
@@ -52 +52 @@
-    *t.get(0)
+    *&t[0]
note rewrite.recursive: 1 site is inside the function its replacement calls there (the function would call itself); first: tab.vl:33:9 in <tab::Tab as Index>::index; rewritten too (--force)
$ rewrite '$t.get($i)' '&$t[$i]' --not-in tab.vl:33 --not-in first --dry-run
--- a/tab.vl
+++ b/tab.vl
@@ -44 +44 @@
-    *t.get(i)
+    *&t[i]
@@ -48 +48 @@
-    *t.get(i)
+    *&t[i]
$ rewrite '$t.get($i)' '&$t[$i]' --not-in tab.vl --dry-run
note rewrite.none: nothing matches '$t.get($i)'
$ rewrite 'at($t, $i)' 'raw_at($t, $i)' --not-in nope.vl
error rewrite.bad-in: no file, module or item 'nope.vl' in the program
[exit 1]
