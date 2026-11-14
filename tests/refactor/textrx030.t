## volec rewrite --text --regex, 0.30 (tests/refactor/textrx030/): the
## dialect has groups and alternatives; NEW takes a match's groups.
## A group that is optional, and the groups in NEW (`\1`, or `$1`).
$ rewrite --text '^fn (\w+)\((mut )?cx: Ctx' 'fn \1(\2cx: &mut Ctx' --regex --dry-run --diff
a.txt	2 matches
would rewrite 2 matches in 1 file
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
-fn make_node(mut cx: Ctx, n: i64)
-fn other(cx: Ctx)
+fn make_node(mut cx: &mut Ctx, n: i64)
+fn other(cx: &mut Ctx)
$ rewrite --text 'alloc_array::<(\w+)>\((\w+)\)' 'Vec::<$1>::with($2)' --regex --dry-run --diff
a.txt	1 match
would rewrite 1 match in 1 file
--- a/a.txt
+++ b/a.txt
@@ -3 +3 @@
-let x = alloc_array::<u8>(n);
+let x = Vec::<u8>::with(n);
## `^` and `$` are a line's ends; `\s`; alternatives; `\0` is the match.
$ rewrite --text '\s+$' '' --regex --dry-run --diff
a.txt	1 match
would rewrite 1 match in 1 file
--- a/a.txt
+++ b/a.txt
@@ -4 +4 @@
-  trailing  
+  trailing
$ rewrite --text '^(foo|let) ?' '<\0>' --regex --dry-run --diff
a.txt	2 matches
would rewrite 2 matches in 1 file
--- a/a.txt
+++ b/a.txt
@@ -3 +3 @@
-let x = alloc_array::<u8>(n);
+<let >x = alloc_array::<u8>(n);
@@ -5 +5 @@
-foo(bar) baz
+<foo>(bar) baz
$ rewrite --text '(foo|baz)' '<\0>' --regex --dry-run --diff
a.txt	2 matches
would rewrite 2 matches in 1 file
--- a/a.txt
+++ b/a.txt
@@ -5 +5 @@
-foo(bar) baz
+<foo>(bar) <baz>
## A parenthesis, a `$`, a `|` as bytes: escaped.
$ rewrite --text 'foo\(bar\)' 'X' --regex --dry-run --diff
a.txt	1 match
would rewrite 1 match in 1 file
--- a/a.txt
+++ b/a.txt
@@ -5 +5 @@
-foo(bar) baz
+X baz
$ rewrite --text 'cost: \$\d' 'free' --regex --dry-run --diff
a.txt	1 match
would rewrite 1 match in 1 file
--- a/a.txt
+++ b/a.txt
@@ -6 +6 @@
-cost: $5
+free
## What is wrong with OLD, by name; a group NEW names and OLD has not.
$ rewrite --text 'foo(bar' 'X' --regex --dry-run
error rewrite.usage: OLD is no regular expression: a `(` that is not closed (a parenthesis as a byte is `\(`) (the dialect: . [a-z] [^x] \d \w \s, * + ? after a byte or a group, ( ) groups, | alternatives, ^ $ the line's ends; \x the byte x)
[exit 2]
$ rewrite --text 'foo)' 'X' --regex --dry-run
error rewrite.usage: OLD is no regular expression: a `)` without its `(` (a parenthesis as a byte is `\)`) (the dialect: . [a-z] [^x] \d \w \s, * + ? after a byte or a group, ( ) groups, | alternatives, ^ $ the line's ends; \x the byte x)
[exit 2]
$ rewrite --text '*foo' 'X' --regex --dry-run
error rewrite.usage: OLD is no regular expression: a `*`, `+` or `?` with nothing to repeat (as a byte: `\*`) (the dialect: . [a-z] [^x] \d \w \s, * + ? after a byte or a group, ( ) groups, | alternatives, ^ $ the line's ends; \x the byte x)
[exit 2]
$ rewrite --text '[a-' 'X' --regex --dry-run
error rewrite.usage: OLD is no regular expression: a `[` that is not closed (as a byte: `\[`) (the dialect: . [a-z] [^x] \d \w \s, * + ? after a byte or a group, ( ) groups, | alternatives, ^ $ the line's ends; \x the byte x)
[exit 2]
$ rewrite --text 'foo' '\1' --regex --dry-run
error rewrite.usage: NEW names group 1 (`\N`, `$N`), OLD has 0 groups: a group is `( )` in OLD; a `$` or `\` before a digit that is text is not written with --regex
[exit 2]
$ rewrite --text '(f)oo' '$2' --regex --dry-run
error rewrite.usage: NEW names group 2 (`\N`, `$N`), OLD has 1 group: a group is `( )` in OLD; a `$` or `\` before a digit that is text is not written with --regex
[exit 2]
## Written, one edit.
$ rewrite --text '(\w+)\((\w+)\) (\w+)' '\3(\2) \1' --regex
a.txt	1 match
rewrote 1 match in 1 file
% cat a.txt
fn make_node(mut cx: Ctx, n: i64)
fn other(cx: Ctx)
let x = alloc_array::<u8>(n);
  trailing  
baz(bar) foo
cost: $5
$ undo
undid rewrote --text '(\w+)\((\w+)\) (\w+)' '\3(\2) \1'	1 files	1 matches
