## (0.25.2) Program roots: from a directory with no main.vl (the root of
## a tree), a FILE or FILE:LINE argument names its program (the main.vl
## that declares it), `--root DIR` is DIR/main.vl, and a NAME is looked
## for in the programs under the directory. try: lines say --root.
$ query context alpha/util.vl:2
// crate::util::twice	alpha/util.vl:1-4	effects: none
pub fn twice(x: i64) -> i64 {
    let y = x + x;
    y
}
// callers (1)
main	alpha/main.vl:5:19	let v = util::twice(21) + util::sum3(1, 2, 3);
$ query items alpha/util.vl
# crate::util	alpha/util.vl
1	fn	pub fn twice(x: i64) -> i64
6	fn	pub fn sum3(a: i64, b: i64, c: i64) -> i64
$ query items --root beta
crate	beta/main.vl	2
$ check alpha/util.vl
ok: 0 errors in alpha/main.vl
## A NAME one program defines: answered from it, with a note.
$ query def only_in_beta
crate::only_in_beta	beta/main.vl:2:4	fn	fn only_in_beta() -> i64	effects: none
note query.other-root: not in this directory's program; answered from beta/main.vl (--root beta/main.vl)
## A NAME several define: a try: line each, with its --root.
$ query def main
error query.no-root: no root (VOLE_ROOT, ./main.vl, ./compiler/src/main.vl)
try: volec query def main --root alpha/main.vl
try: volec query def main --root beta/main.vl
[exit 2]
$ query def nowhere_defined
error query.no-root: no root (VOLE_ROOT, ./main.vl, ./compiler/src/main.vl)
try: volec query def nowhere_defined path/to/main.vl
[exit 2]
## edit patch on another program's file; --all replaces every match.
$ edit patch alpha/util.vl --old ' + 0' --new '' --all
patched crate::util	alpha/util.vl	+3 -3 lines
% cat alpha/util.vl
pub fn twice(x: i64) -> i64 {
    let y = x + x;
    y
}

pub fn sum3(a: i64, b: i64, c: i64) -> i64 {
    let s = a;
    let t = s + b;
    t + c
}
$ edit patch alpha/util.vl:2 --old 'x' --new 'x * 2'
error patch.ambiguous: OLD 1 occurs 3 times in crate::util::twice, lines 1, 2, 2; give more of the text around it, or --nth N (--all: every one)
try: volec edit patch alpha/util.vl:2 --root alpha/main.vl --old 'pub fn twice(x: i64) -> i64 {' --new 'pub fn twice(x * 2: i64) -> i64 {'
try: volec edit patch alpha/util.vl:2 --root alpha/main.vl --old 'let y = x + x;' --new 'let y = x * 2 + x;'
try: volec edit patch alpha/util.vl:2 --root alpha/main.vl --old 'let y = x + x;' --new 'let y = x + x * 2;'
[exit 1]
## probe runs the program FILE belongs to; its arguments follow `--`,
## and its try: lines keep them.
$ probe alpha/util.vl:2 x -- one two
probe alpha/util.vl:2 (after `let y = x + x;`): 1 time
  #1  x = 21
run: exit 0; stdout 1 line (target/scratch/probe/alpha-main.vl/out)
  | 48
$ probe alpha/util.vl:3 y -- one two
probe alpha/util.vl:3 (before `y`): 1 time
  #1  y = 42
run: exit 0; stdout 1 line (target/scratch/probe/alpha-main.vl/out)
  | 48
$ probe alpha/util.vl:5 t -- one two
error probe.no-statement: alpha/util.vl:5 begins no statement and opens no block; a probe goes at a line that does
try: volec probe --root alpha/main.vl alpha/util.vl:7 t -- one two
try: volec probe --root alpha/main.vl alpha/util.vl:2 t -- one two
[exit 1]
## (0.25.2) The probes' copies are never in the source tree, and are gone
## after the run (the build and outputs: target/scratch/probe/NAME/).
% find . -name '*.probe' -o -name .volec | sort; ls -A alpha; ls target/scratch/probe/alpha-main.vl
main.vl
util.vl
err
out
prog
