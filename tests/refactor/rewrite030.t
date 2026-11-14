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
tab.vl:25:9	$t=self	$i=i	&self.rows[i]
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
## Patterns of 0.30. A hole for the name of a field, of a method; --list
## ends with the site's source line.
$ rewrite '$e.$f' --list --in main
main.vl:9:13	$e=at(&t, 0)	$f=reg	let a = at(&t, 0).reg;
main.vl:10:13	$e=raw_at(&t, 1)	$f=len	let b = raw_at(&t, 1).len;
main.vl:11:13	$e=(at(&t, (1)))	$f=len	let c = (at(&t, (1))).len;
main.vl:12:13	$e=first(&t)	$f=reg	let d = first(&t).reg + (0);
$ rewrite '$e.$f~/^re/' --list
main.vl:9:13	$e=at(&t, 0)	$f=reg	let a = at(&t, 0).reg;
main.vl:12:13	$e=first(&t)	$f=reg	let d = first(&t).reg + (0);
$ rewrite 'at($t, $i).$f' 'raw_at($t, $i).$f' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-use crate::tab::{Row, Tab, at, first, raw_at, tag, twice_len};
+use crate::tab::{Row, Tab, first, raw_at, tag, twice_len};
@@ -9 +9 @@
-    let a = at(&t, 0).reg;
+    let a = raw_at(&t, 0).reg;
@@ -11 +11 @@
-    let c = (at(&t, (1))).len;
+    let c = raw_at(&t, 1).len;
note rewrite.imports: removed 1 import the rewrite left unused
$ rewrite '$e.$m($a...)' --list --in main
main.vl:7:5	$e=t	$m=push	$a...=Row { reg: 1, len: 2 }	t.push(Row { reg: 1, len: 2 });
main.vl:8:5	$e=t	$m=push	$a...=Row { reg: 3, len: 4 }	t.push(Row { reg: 3, len: 4 });
main.vl:13:34	$e=b"abc"	$m=len	$a...=	let n = twice_len(b"vole") + b"abc".len() as i64 * 2;
$ rewrite '$t.$m($i)' 'Tab::$m($t, $i)' --in at --dry-run
--- a/tab.vl
+++ b/tab.vl
@@ -44 +44 @@
-    *t.get(i)
+    *Tab::get(t, i)
## A hole where none can stand is an error, not `nothing matches`.
$ rewrite 'Row { $f: 1, len: 2 }' --list
error rewrite.pattern: $f stands where no hole can: a hole is an expression, a type, a binding (`let $x`, `for $x in`), the name of a field or a method (`$e.$f`, `$e.$m()`), the text of a string literal (`c"$s"`)
[exit 2]
## Parentheses. The site's go when the replacement needs none there, and
## a hole's where it lands in an argument; a literal and a hole match
## through redundant ones.
$ rewrite 'at($t, $i)' 'raw_at($t, $i)' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-use crate::tab::{Row, Tab, at, first, raw_at, tag, twice_len};
+use crate::tab::{Row, Tab, first, raw_at, tag, twice_len};
@@ -9 +9 @@
-    let a = at(&t, 0).reg;
+    let a = raw_at(&t, 0).reg;
@@ -11 +11 @@
-    let c = (at(&t, (1))).len;
+    let c = raw_at(&t, 1).len;
note rewrite.imports: removed 1 import the rewrite left unused
$ rewrite 'at($t, 1)' --list
main.vl:11:13	$t=&t	let c = (at(&t, (1))).len;
$ rewrite '$a + 0' '$a' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -12 +12 @@
-    let d = first(&t).reg + (0);
+    let d = first(&t).reg;
$ rewrite '$x.len' '$x.reg' --in main --dry-run
--- a/main.vl
+++ b/main.vl
@@ -10,2 +10,2 @@
-    let b = raw_at(&t, 1).len;
-    let c = (at(&t, (1))).len;
+    let b = raw_at(&t, 1).reg;
+    let c = at(&t, (1)).reg;
## (the ones the replacement needs are still added)
$ rewrite 'first($t)' '*$t.get(0)' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-use crate::tab::{Row, Tab, at, first, raw_at, tag, twice_len};
+use crate::tab::{Row, Tab, at, raw_at, tag, twice_len};
@@ -12 +12 @@
-    let d = first(&t).reg + (0);
+    let d = (*(&t).get(0)).reg + (0);
note rewrite.imports: removed 1 import the rewrite left unused
## A literal's text: `c"$s"` is any C-string literal, and only those.
$ rewrite 'c"$s"' --list
main.vl:14:17	$s=malloc	let m = tag(c"malloc") + tag(c"calloc");
main.vl:14:34	$s=calloc	let m = tag(c"malloc") + tag(c"calloc");
$ rewrite 'b"$s"' --list
main.vl:13:23	$s=vole	let n = twice_len(b"vole") + b"abc".len() as i64 * 2;
main.vl:13:34	$s=abc	let n = twice_len(b"vole") + b"abc".len() as i64 * 2;
$ rewrite 'c"$s"' 'b"$s\0".as_ptr()' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -14 +14 @@
-    let m = tag(c"malloc") + tag(c"calloc");
+    let m = tag(b"malloc\0".as_ptr()) + tag(b"calloc\0".as_ptr());
## --from FILE: the rewrites of a file, a line each, in order (the second
## line matches what the first wrote), checked once: one edit.
% cat pairs.txt
at($t, $i) -> raw_at($t, $i)
# the first line's results too; a TAB, then the line's options

raw_at($t, 1).len	raw_at($t, 1).reg
$s.len() as i64 * 2	twice_len($s)	--not-in twice_len
$ rewrite --from pairs.txt --dry-run
rewrote 2 sites in 1 file	main.vl	+3 -3 lines
rewrote 2 sites in 1 file	main.vl	+2 -2 lines
rewrote 1 site in 1 file	main.vl	+1 -1 lines
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-use crate::tab::{Row, Tab, at, first, raw_at, tag, twice_len};
+use crate::tab::{Row, Tab, first, raw_at, tag, twice_len};
@@ -9,3 +9,3 @@
-    let a = at(&t, 0).reg;
-    let b = raw_at(&t, 1).len;
-    let c = (at(&t, (1))).len;
+    let a = raw_at(&t, 0).reg;
+    let b = raw_at(&t, 1).reg;
+    let c = raw_at(&t, 1).reg;
@@ -13 +13 @@
-    let n = twice_len(b"vole") + b"abc".len() as i64 * 2;
+    let n = twice_len(b"vole") + twice_len(b"abc");
note rewrite.imports: removed 1 import the rewrite left unused
$ rewrite --from pairs.txt
rewrote 2 sites in 1 file	main.vl	+3 -3 lines
rewrote 2 sites in 1 file	main.vl	+2 -2 lines
rewrote 1 site in 1 file	main.vl	+1 -1 lines
rewrite --from pairs.txt: 3 patterns	main.vl	+5 -5 lines
note rewrite.imports: removed 1 import the rewrite left unused
$ undo
undid rewrite --from pairs.txt: 3 patterns	main.vl	+5 -5 lines
## A line that fails ends it: nothing written.
$ rewrite --from pairs_rec.txt
rewrote 2 sites in 1 file	main.vl	+3 -3 lines
note rewrite.imports: removed 1 import the rewrite left unused
error rewrite.recursive: 1 site is inside the function its replacement calls there (the function would call itself); first: tab.vl:57:5 in tab::twice_len; nothing written
try: volec rewrite '$s.len() as i64 * 2' 'twice_len($s)' --root main.vl --not-in tab::twice_len
try: volec rewrite '$s.len() as i64 * 2' 'twice_len($s)' --root main.vl --force
error refactor.script: pairs_rec.txt:2: the command failed (exit 1): rewrite '$s.len() as i64 * 2' 'twice_len($s)'; nothing written
[exit 1]
$ rewrite --from pairs_bad.txt
error rewrite.from: pairs_bad.txt:1: several ` -> `: put a TAB between PATTERN and REPLACEMENT; nothing run
[exit 2]
$ rewrite --from pairs.txt --where '$t: &Tab'
error rewrite.usage: '$t: &Tab' with --from: the patterns and their options (--where, --subst) are FILE's lines, `PATTERN -> REPLACEMENT` or PATTERN<TAB>REPLACEMENT<TAB>OPTIONS; the command takes --in, --not-in, --force, --dry-run, --no-check, --root
[exit 2]
% git status --short
## The import a replacement's name needs, in every file: 210 files, more
## than a check reports errors (50) in the four rounds an edit has.
% sh gen_bulk.sh 210
$ rewrite 'old_fn($x)' 'new_fn($x)' --root bulk/main.vl
rewrote 210 sites in 210 files	210 files	+420 -420 lines
note rewrite.imports: removed 210 imports the rewrite left unused
note edit.imports: added the imports the new text needs (fix --only imports)
% cat bulk/m7.vl
use crate::lib2::new_fn;

pub fn f() -> i64 {
    new_fn(7)
}
