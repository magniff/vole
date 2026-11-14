## refactor field --type, 0.30 (tests/refactor/field030/): a struct made
## generic over its allocator, several fields, their uses rewritten, in
## one checked edit.
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
## A new type that names a parameter the struct has not is an error that
## says what to add, not `unknown type 'A'` after the edit.
$ refactor field Cx --type regs 'Vec<i64, A>'
error refactor.usage: 'A' in the new type is no parameter of crate::Cx and no type: `--allocator X` (the allocator its uses have: Gpa, an arena's type) makes the struct generic over its allocator, `Cx<A: Allocator>`, and names X at its uses, in this edit
[exit 2]
## --allocator X: the field holds X, and before the check the rounds of
## `fix --only alloc` make the struct generic over it and name X at its
## uses. The literal still has its old value: the check refuses the edit,
## and the note says which literals keep theirs.
$ refactor field Cx --type regs 'Vec<i64, A>' --allocator Gpa
main.vl:33:5: error[type error] expected 'i64', got 'Option<&i64>'  [edited: crate::total]
main.vl:44:29: error[type error] expected 'Vec<i64, _>', got 'IntVec'  [in crate::main]
note edit.rounds: 2 rounds of `fix --only alloc` on the edited program, in the same edit
error edit.breaks: 2 new errors (1 in the edited text, 1 in crate::main, which the edit does not change); nothing written; the first in the edited text: main.vl:33:5: expected 'i64', got 'Option<&i64>'
note edit.refactor: the uses of crate::total no longer fit its new shape: a refactoring changes them with it (VALUE, EXPR: to fill in), then the rest of the edit
try: volec refactor signature crate::total --type cx '&Cx<Gpa>' --default EXPR
try: volec refactor field crate::Cx --type regs 'Vec<i64, A>'
try: volec refactor signature crate::fill --type cx '&mut Cx<Gpa>' --default EXPR
note edit.together: change crate::main in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::main
try: volec refactor field Cx --type regs 'Vec<i64, A>' --allocator Gpa --no-check
note refactor.literals: 1 literal of crate::Cx keeps the value it had for regs (main.vl:42:23): --default EXPR gives each its new value (`$regs` in EXPR: the old one)
[exit 1]
## --default EXPR gives the literals their value; what is left is the use
## that no longer fits.
$ refactor field Cx --type regs 'Vec<i64, A>' --allocator Gpa --default 'Vec::new_in(gpa)' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -2,0 +3,2 @@
+use std::alloc::Allocator;
+
@@ -23,2 +25,2 @@
-struct Cx {
-    regs: IntVec,
+struct Cx<A: Allocator> {
+    regs: Vec<i64, A>,
@@ -30 +32 @@
-fn total(cx: &Cx) -> i64 {
+fn total(cx: &Cx<Gpa>) -> i64 {
@@ -34 +36 @@
-fn fill(cx: &mut Cx) {
+fn fill(cx: &mut Cx<Gpa>) {
@@ -42 +44 @@
-    let mut cx = Cx { regs: IntVec::new(), uses: IntVec::new(), spare: IntVec::new(), depth: 0 };
+    let mut cx = Cx { regs: Vec::new_in(gpa), uses: IntVec::new(), spare: IntVec::new(), depth: 0 };
main.vl:33:5: error[type error] expected 'i64', got 'Option<&i64>'  [edited: crate::total]
note edit.rounds: 2 rounds of `fix --only alloc` on the edited program, in the same edit
warning edit.breaks: 1 new error (dry run); the error: main.vl:33:5: expected 'i64', got 'Option<&i64>'
[exit 1]
## --rewrite PAT REPL: `$f` in PAT is an access of the field, typed as the
## program is before the change. Several fields, `f,g`: all of it is one
## edit, checked once.
$ refactor field Cx --type regs,uses 'Vec<i64, A>' --allocator Gpa --default 'Vec::new_in(gpa)' --rewrite '$f.get($i)' '$f[$i as usize]'
changed fields regs, uses to Vec<i64, A> in crate::Cx, 2 literals, 2 uses rewritten	main.vl	+11 -7 lines
note edit.rounds: 2 rounds of `fix --only alloc` on the edited program, in the same edit
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
% sed -n '/^struct Cx/,$p' main.vl
struct Cx<A: Allocator> {
    regs: Vec<i64, A>,
    uses: Vec<i64, A>,
    spare: IntVec,
    depth: i64,
}

fn total(cx: &Cx<Gpa>) -> i64 {
    cx.regs[0 as usize] + cx.uses[1 as usize] + cx.spare.get(0) + cx.depth
}

fn fill(cx: &mut Cx<Gpa>) {
    cx.regs.push(1);
    cx.uses.push(2);
    cx.uses.push(3);
    cx.spare.push(4);
}

fn main(gpa: Gpa) -> i32 {
    let mut cx = Cx {
        regs: Vec::new_in(gpa), uses: Vec::new_in(gpa), spare: IntVec::new(), depth: 0,
    };
    fill(&mut cx);
    total(&cx) as i32
}
$ undo
undid changed fields regs, uses to Vec<i64, A> in crate::Cx, 2 literals, 2 uses rewritten	main.vl	+11 -7 lines
## The same accesses, for a rewrite: --where '$x: field STRUCT.NAME'.
$ rewrite '$f.get($i)' --list --where '$f: field Cx.regs,spare'
main.vl:31:5	$f=cx.regs	$i=0	cx.regs.get(0) + cx.uses.get(1) + cx.spare.get(0) + cx.depth
main.vl:31:39	$f=cx.spare	$i=0	cx.regs.get(0) + cx.uses.get(1) + cx.spare.get(0) + cx.depth
$ rewrite '$f.get($i)' '$f.get($i + 0)' --where '$f: field Cx.spare' --dry-run
--- a/main.vl
+++ b/main.vl
@@ -31 +31 @@
-    cx.regs.get(0) + cx.uses.get(1) + cx.spare.get(0) + cx.depth
+    cx.regs.get(0) + cx.uses.get(1) + cx.spare.get(0 + 0) + cx.depth
$ rewrite '$f.get($i)' --list --where '$f: field Cx.nope'
error rewrite.usage: --where '$x: field STRUCT.NAME' (or NAME,NAME) names fields of one struct of the program: 'Cx.nope' has no such field
[exit 2]
$ rewrite '$f.get($i)' --list --where '$f: field Nope.regs'
error rewrite.usage: --where '$x: field STRUCT.NAME' (or NAME,NAME) names fields of one struct of the program: 'Nope.regs' has no such struct
[exit 2]
## Written unchecked: the literals that keep their old value are named.
$ refactor field Cx --type regs 'Vec<i64, Gpa>' --no-check
changed field regs to Vec<i64, Gpa> in crate::Cx	main.vl	+1 -1 lines
warning refactor.literals: 1 literal of crate::Cx keeps the value it had for regs (main.vl:42:23): --default EXPR gives each its new value (`$regs` in EXPR: the old one)
$ undo
undid changed field regs to Vec<i64, Gpa> in crate::Cx	main.vl	+1 -1 lines
## Usage.
$ refactor field Cx --rename regs r --allocator Gpa
error refactor.usage: --rewrite and --allocator go with --type
try: volec refactor field STRUCT --type f,g 'Vec<i64, A>' --allocator Gpa --rewrite '$f.get($i)' '$f[$i]'
[exit 2]
$ refactor field Cx --type nope,regs i64
error refactor.no-member: crate::Cx has no field 'nope': { regs, uses, spare, depth }
try: volec query show crate::Cx
[exit 1]
$ refactor field Cx --type regs i64 --rewrite '$g.get($i)' '$g[$i]'
error refactor.usage: --rewrite's PATTERN names the access of the field as the hole `$f`
try: volec refactor field STRUCT --type f T --rewrite '$f.get($i)' '$f[$i]'
[exit 2]
