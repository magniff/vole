## volec rewrite and std's files, 0.30 (tests/refactor/rewritestd030/).
## Where std has no files (here: VOLE_STD_TREE=none, as outside the vole
## repository) std is the compiler's own text, and the rewrite says that
## it does not search it.
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
$ rewrite '$x.is_none()' '!$x.is_some()' --in std
note rewrite.std: std is the compiler's own text here, not files (no compiler/std around, or VOLE_STD_TREE=none): rewrite does not search it; in the vole repository `--in std` rewrites compiler/std's files
$ rewrite '$x.is_none()' --list --in std
note rewrite.std: std is the compiler's own text here, not files (no compiler/std around, or VOLE_STD_TREE=none): rewrite does not search it; in the vole repository `--in std` rewrites compiler/std's files
## A copy of the repository's std with one more module, t30probe, stands
## in for compiler/std: asked for, std is read from its files, searched
## and written.
% mkdir compiler && cp -R $T/../../compiler/std compiler/std && cp probe.vl compiler/std/t30probe.vl && echo 'pub mod t30probe;' >> compiler/std/std.vl
% VOLE_STD_TREE=compiler/std volec rewrite '$a + $a' --list --in compiler/std/t30probe.vl
compiler/std/t30probe.vl:3:5	$a=x	x + x
compiler/std/t30probe.vl:7:5	$a=x	(x + x) + (x + x)
compiler/std/t30probe.vl:7:5	$a=(x + x)	(x + x) + (x + x)
compiler/std/t30probe.vl:7:15	$a=x	(x + x) + (x + x)
% VOLE_STD_TREE=compiler/std volec rewrite '$a + $a' '2 * $a' --in std::t30probe --dry-run
--- a/compiler/std/t30probe.vl
+++ b/compiler/std/t30probe.vl
@@ -3 +3 @@
-    x + x
+    2 * x
@@ -7 +7 @@
-    (x + x) + (x + x)
+    2 * (x + x)
note rewrite.nested: 2 sites inside rewritten ones are left; run the rewrite again
% VOLE_STD_TREE=compiler/std volec rewrite '$a + $a' '2 * $a' --in compiler/std/t30probe.vl
rewrote 2 sites in 1 file of std	compiler/std/t30probe.vl	+2 -2 lines
note rewrite.nested: 2 sites inside rewritten ones are left; run the rewrite again
note rewrite.std: std's files are rewritten, not the std built into the compiler: run `sh compiler/std/embed.sh`, then build (bootstrap/bootstrap.sh --dev --no-suite); checked with main.vl: what it uses of std
% cat compiler/std/t30probe.vl
// A module of the copied std, for the transcript: no program uses it.
pub fn twice(x: i64) -> i64 {
    2 * x
}

pub fn four(x: i64) -> i64 {
    2 * (x + x)
}
## (the sites inside the function the replacement calls, in std too)
% VOLE_STD_TREE=compiler/std volec rewrite '2 * $a' 'twice($a)' --in compiler/std/t30probe.vl
error rewrite.recursive: 1 site is inside the function its replacement calls there (the function would call itself); first: compiler/std/t30probe.vl:3:5 in std::t30probe::twice; nothing written
try: volec rewrite '2 * $a' 'twice($a)' --in compiler/std/t30probe.vl --not-in std::t30probe::twice
try: volec rewrite '2 * $a' 'twice($a)' --in compiler/std/t30probe.vl --force
[exit 1]
## One edit, which undo takes back (undo's embed.sh has no compiler here).
% VOLE_STD_TREE=compiler/std volec undo 2>/dev/null
undid rewrote 2 sites in 1 file of std
% diff probe.vl compiler/std/t30probe.vl && echo same
same
## The program is checked with std's new texts: what it uses of std.
% VOLE_STD_TREE=compiler/std volec rewrite 'self.is_some()' 'nope(self)' --in compiler/std/option.vl 2>&1 | grep -c 'error edit.breaks'
1
## Not a file of std; the program's sites and std's in one run.
% VOLE_STD_TREE=compiler/std volec rewrite '$a + $a' '2 * $a' --in compiler/std/nope.vl
error rewrite.bad-in: std has no file 'compiler/std/nope.vl'
[exit 1]
% VOLE_STD_TREE=compiler/std volec rewrite '$x.is_none()' '!$x.is_some()' --in std --in main.vl 2>&1 | sed -E 's/: [0-9]+ sites? (are|is) in std/: N sites are in std/'
error rewrite.std: N sites are in std's files and 1 in the program's: std is rewritten in a run of its own (--in std alone), the program in another; nothing written
