# Fix the errors

`gradebook` reads a class's test scores and prints each student's
average, grade and biggest swing between tests. It was written in a
hurry and half-changed: it does not compile. Three
files, about 130 lines, nine errors.

The session gets it to build the way an agent should: every error at
once, one line each; the mechanical ones fixed by `volec fix`; the
rest fixed by name with `edit patch` and `edit apply`, each edit checked
before it is written. Every command below is run by
`tests/walkthrough/run.sh` on a fresh copy of this directory, and its
output is checked against this file. (This directory is the one example
that is meant not to compile.)

## 1. Every error, one line each

A build stops at the errors; `check` runs only the front end (parse,
names, types, unsafe), which is fast, and prints every error of every
file, one per line, `FILE:LINE:COL: error[KIND] MESSAGE | help: ...`:

```console
$ volec check
main.vl:9:38: error[item.private] 'letter' is private | help: make it public: `pub fn letter` at grades.vl:22:1 | try: volec fix --suggested main.vl
main.vl:10:14: error[type error] unresolved import 'roster::add_score'
main.vl:17:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
main.vl:18:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
main.vl:19:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
main.vl:23:19: error[type error] unknown type 'HashMap' | help: add `use std::collections::hash_map::HashMap;` | try: volec fix --suggested main.vl
grades.vl:19:5: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
grades.vl:40:17: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
roster.vl:29:13: error[type error] cannot assign to immutable variable 'count' | help: make it mutable: `let mut count`
[exit 1]
```

Most say what to do, in their `help:`. A `KIND` (`type error`,
`unsafe`, ...) or a tool's code (`patch.no-match`) is explained by
`explain`:

```console
$ volec explain unsafe
unsafe: error (compiler)
An unsafe operation (a raw pointer's dereference or indexing, a C call, a union field, a `static mut`) outside unsafe code.
fix: Put it in an `unsafe { }` block, or the function in `unsafe fn`; the try: line, `volec fix --only unsafe ROOT`, wraps every such place (the check hook prints it once, with how many errors it answers). A raw pointer parameter that only reads or writes one value: take a reference, `x: &T`, or `x: &mut T` when written through, and keep `*const T` and `*mut T` for what stays raw (indexed, compared, cast, stored, given to C).
example:
    fn first(p: *const i64) -> i64 {
        *p
    }
    
    fn main() {
        let x = 5;
        println("{}", first(&raw const x));
    }
    
    main.vl:2:5: error[unsafe] dereference of a raw pointer is unsafe
      help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place)
      try: volec fix --only unsafe main.vl
```

## 2. The mechanical ones: `fix`

A missing `use` line, an item that must become `pub`, a C call outside
`unsafe`: these have exactly one fix, and `fix` makes them all in one
edit. (An error whose `try:` is `volec fix --suggested` has an exact
fix the compiler knows, `totl` for `total` too: `fix --suggested` makes
those, then prints the errors left; `totl` is fixed by hand below, to
show `edit patch`.) `--dry-run` shows the diff first:

```console
$ volec fix --dry-run
--- a/main.vl
+++ b/main.vl
@@ -8,0 +9,2 @@
+use std::collections::hash_map::HashMap;
+
--- a/grades.vl
+++ b/grades.vl
@@ -22 +22 @@
-fn letter(avg: i64) -> char {
+pub fn letter(avg: i64) -> char {
@@ -40 +40 @@
-        let d = abs((scores[i] - scores[i - 1]) as i32) as i64;
+        let d = unsafe { abs((scores[i] - scores[i - 1]) as i32) as i64 };
$ volec fix
fixed 1 missing import, 1 pub, 1 unsafe block	2 files	+4 -2 lines
$ volec check
main.vl:12:14: error[type error] unresolved import 'roster::add_score'
main.vl:19:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
main.vl:20:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
main.vl:21:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
grades.vl:19:5: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
roster.vl:29:13: error[type error] cannot assign to immutable variable 'count' | help: make it mutable: `let mut count`
[exit 1]
```

## 3. The ones that need a decision: `edit patch`

The item at an error's position is `query show FILE:LINE`:

```console
$ volec query show roster.vl:29
// crate::roster::with_scores	roster.vl:24-33
// How many students have at least `n` scores.
pub fn with_scores(r: &Roster<Gpa>, n: usize) -> usize {
    let count = 0;
    for s in r.students.iter() {
        if s.scores.len() >= n {
            count += 1;
        }
    }
    count
}
warning query.program-errors: 6 errors in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
```

`edit patch` changes text inside one item, named by name or by a
`FILE:LINE` inside it; OLD must occur exactly once in that item:

```console
$ volec edit patch roster.vl:29 --old 'let count' --new 'let mut count' --show
patched crate::roster::with_scores	roster.vl	+1 -1 lines
// roster.vl:26
26	    let mut count = 0;
```

An OLD that is not there is refused, with the nearest line of the item
and a `try:` command built from it. Here it shows that the source
writes the cast without parentheses:

```console
$ volec edit patch grades.vl:19 --old 'totl / (scores.len() as i64)' --new 'total / (scores.len() as i64)'
error patch.no-match: OLD 1 is not in crate::grades::average; nearest, line 19: totl / scores.len() as i64
try: volec edit patch grades.vl:19 --old 'totl / scores.len() as i64' --new 'total / (scores.len() as i64)'
[exit 1]
$ volec edit patch grades.vl:19 --old 'totl' --new 'total' --show
patched crate::grades::average	grades.vl	+1 -1 lines
// grades.vl:19
19	    total / scores.len() as i64
```

## 4. A fix that spans items: `edit apply`

What is left is one change seen from two sides: `main` calls
`enrol(&mut r, name, scores)` and imports `add_score`, but `roster` has a
two-argument `enrol` and no `add_score`.

```console
$ volec check
main.vl:12:14: error[type error] unresolved import 'roster::add_score'
main.vl:19:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
main.vl:20:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
main.vl:21:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str)` (roster.vl:20)
[exit 1]
$ volec query show roster::enrol
// crate::roster::enrol	roster.vl:19-22	effects: alloc(Gpa) panic
// A student with no scores yet.
pub fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str) {
    r.students.push(Student { name, scores: Vec::new_in(*r.students.allocator()) });
}
warning query.program-errors: 4 errors in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
```

`edit apply` takes the new text of several items as blocks: `@@ NAME`
replaces an item, `@@ new after NAME` adds one, `@@ delete NAME`
removes one. All the blocks are one edit: checked together, written
together, undone together. (The output of `query show A B`, edited, is
a valid input.)

```console
$ volec edit apply --show <<'EOF'
> @@ roster::enrol
> // A student and their scores so far.
> pub fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str, scores: &[i64]) {
>     let mut v: Vec<i64, Gpa> = Vec::new_in(*r.students.allocator());
>     v.extend_from_slice(scores);
>     r.students.push(Student { name, scores: v });
> }
> @@ new after roster::enrol
> // One more score for the student called `name`; false when there is none.
> pub fn add_score(r: &mut Roster<Gpa>, name: &str, score: i64) -> bool {
>     for i in 0..r.students.len() {
>         if r.students[i].name == name {
>             r.students[i].scores.push(score);
>             return true;
>         }
>     }
>     false
> }
> EOF
applied 2 blocks: replaced crate::roster::enrol; inserted after crate::roster::enrol	roster.vl	+16 -3 lines
// roster.vl:19-34
19	// A student and their scores so far.
20	pub fn enrol<'a>(r: &mut Roster<'a, Gpa>, name: &'a str, scores: &[i64]) {
21	    let mut v: Vec<i64, Gpa> = Vec::new_in(*r.students.allocator());
22	    v.extend_from_slice(scores);
23	    r.students.push(Student { name, scores: v });
24	}
25	
26	// One more score for the student called `name`; false when there is none.
27	pub fn add_score(r: &mut Roster<Gpa>, name: &str, score: i64) -> bool {
28	    for i in 0..r.students.len() {
29	        if r.students[i].name == name {
30	            r.students[i].scores.push(score);
31	            return true;
32	        }
33	    }
34	    false
```

## 5. It builds

No errors; the two warnings are the C call's unsafe, which says nowhere
why it cannot be safe and why it is sound (`volec explain
unsafe.unjustified`): `fix` wraps the call, the justification is the
author's (`// UNSAFE:` and `// SAFETY:` right above).

```console
$ volec check && echo no errors
no errors
grades.vl:4:1: warning[unsafe.unjustified] extern block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe grades.vl
grades.vl:40:17: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe grades.vl
ok: 0 errors, 2 warnings in main.vl
$ volec main.vl -o gradebook && ./gradebook
Ada     95 A  swing  6, with honours
Brook   75 C  swing 21
Cyd     64 D  swing 17
best: Ada (95); 3 students have 3 scores or more
ok: built gradebook
$ git diff --stat
 grades.vl |  6 +++---
 main.vl   |  2 ++
 roster.vl | 21 +++++++++++++++++----
 3 files changed, 22 insertions(+), 7 deletions(-)
```

## Why not by hand

- Nine errors in three files were listed by one command, before any
  build, each with its position and usually its fix. A compile-edit
  loop would have shown them a few at a time.
- Three of them were fixed by `fix` with no file opened; the edit is the
  same one a careful human would make (`pub fn letter`, an
  `unsafe { }` around the one call, the `use` line for `HashMap`).
- Each other fix named the item it changes, not a line number that
  moves after every edit, and was checked before it was written: a
  patch that had introduced a new error (`scores.size()` on a slice)
  would have been refused, with the error.
- `edit apply` made a change that is only correct as a whole (a new
  signature, a new function) in one step, so there was never a state of
  the program with more errors than before.
