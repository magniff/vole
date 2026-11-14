## refactor fold NAME --as true|false, 0.30 (tests/refactor/fold030/): a
## predicate that is one value from now on, folded away.
$ check
ok: 0 errors in main.vl (2 files, 0 shaders)
% cat main.vl
mod flags;

use crate::flags::{legacy_step, new_step, old_only, on_new, shared, traced};

fn step(x: i64) -> i64 {
    if on_new() {
        return new_step(x);
    }
    // the old way
    let y = old_only(x);
    legacy_step(y)
}

fn pick(x: i64) -> i64 {
    let a = if on_new() { shared(x) } else { old_only(x) };
    let b = if !on_new() && x > 0 { 1 } else if x > 10 { 2 } else { 3 };
    let c = if x > 3 { 4 } else if !on_new() { 5 } else { 6 };
    if x > 5 || on_new() {
        return a + b + c;
    }
    a - b
}

fn walk(n: i64) -> i64 {
    let mut i = 0;
    let mut t = 0;
    while !on_new() {
        t += old_only(i);
    }
    while i < n && on_new() {
        t += i;
        i += 1;
    }
    if traced(shared(1)) && !on_new() {
        t += 100;
    }
    match n {
        0 if on_new() => t,
        1 if !on_new() => old_only(t),
        _ => 2 * (if on_new() { t + 1 } else { t }),
    }
}

fn main() -> i32 {
    (step(1) + pick(2) + walk(3)) as i32
}
## Each call is the constant, and the code around it what the constant
## leaves: the branch taken in the `if`'s place, the statements after a
## `return` that is now unconditional gone, a loop that never runs gone,
## `x && true` as `x`, a guard gone or its arm gone. A side that calls a
## function stays when the constant alone would drop its evaluation
## (`traced(shared(1)) && false`). Then the items whose every use went.
$ refactor fold on_new --as true --dry-run --diff
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-use crate::flags::{legacy_step, new_step, old_only, on_new, shared, traced};
+use crate::flags::{new_step, shared, traced};
@@ -6,6 +6 @@
-    if on_new() {
-        return new_step(x);
-    }
-    // the old way
-    let y = old_only(x);
-    legacy_step(y)
+    return new_step(x);
@@ -15,7 +10,4 @@
-    let a = if on_new() { shared(x) } else { old_only(x) };
-    let b = if !on_new() && x > 0 { 1 } else if x > 10 { 2 } else { 3 };
-    let c = if x > 3 { 4 } else if !on_new() { 5 } else { 6 };
-    if x > 5 || on_new() {
-        return a + b + c;
-    }
-    a - b
+    let a = shared(x);
+    let b = if x > 10 { 2 } else { 3 };
+    let c = if x > 3 { 4 } else { 6 };
+    return a + b + c;
@@ -27,4 +19 @@
-    while !on_new() {
-        t += old_only(i);
-    }
-    while i < n && on_new() {
+    while i < n {
@@ -34 +23 @@
-    if traced(shared(1)) && !on_new() {
+    if traced(shared(1)) && false {
@@ -38,3 +27,2 @@
-        0 if on_new() => t,
-        1 if !on_new() => old_only(t),
-        _ => 2 * (if on_new() { t + 1 } else { t }),
+        0 => t,
+        _ => 2 * (t + 1),
note rewrite.imports: removed 3 imports the fold left unused
note refactor.unused: 3 items have no use left in the program: crate::flags::on_new (flags.vl:2:8), crate::flags::legacy_step (flags.vl:10:8), crate::flags::old_only (flags.vl:14:8)
try: volec edit delete crate::flags::on_new
try: volec edit delete crate::flags::legacy_step
try: volec edit delete crate::flags::old_only
$ refactor fold on_new --as true
folded 11 calls of crate::flags::on_new as true in 3 items	main.vl	+10 -22 lines
note rewrite.imports: removed 3 imports the fold left unused
note refactor.unused: 3 items have no use left in the program: crate::flags::on_new (flags.vl:2:8), crate::flags::legacy_step (flags.vl:10:8), crate::flags::old_only (flags.vl:14:8)
try: volec edit delete crate::flags::on_new
try: volec edit delete crate::flags::legacy_step
try: volec edit delete crate::flags::old_only
$ check
ok: 0 errors in main.vl (2 files, 0 shaders)
% cat main.vl
mod flags;

use crate::flags::{new_step, shared, traced};

fn step(x: i64) -> i64 {
    return new_step(x);
}

fn pick(x: i64) -> i64 {
    let a = shared(x);
    let b = if x > 10 { 2 } else { 3 };
    let c = if x > 3 { 4 } else { 6 };
    return a + b + c;
}

fn walk(n: i64) -> i64 {
    let mut i = 0;
    let mut t = 0;
    while i < n {
        t += i;
        i += 1;
    }
    if traced(shared(1)) && false {
        t += 100;
    }
    match n {
        0 => t,
        _ => 2 * (t + 1),
    }
}

fn main() -> i32 {
    (step(1) + pick(2) + walk(3)) as i32
}
$ undo
undid folded 11 calls of crate::flags::on_new as true in 3 items	main.vl	+10 -22 lines
## The other value.
$ refactor fold on_new --as false --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-use crate::flags::{legacy_step, new_step, old_only, on_new, shared, traced};
+use crate::flags::{legacy_step, old_only, shared, traced};
@@ -6,3 +5,0 @@
-    if on_new() {
-        return new_step(x);
-    }
@@ -15,4 +12,4 @@
-    let a = if on_new() { shared(x) } else { old_only(x) };
-    let b = if !on_new() && x > 0 { 1 } else if x > 10 { 2 } else { 3 };
-    let c = if x > 3 { 4 } else if !on_new() { 5 } else { 6 };
-    if x > 5 || on_new() {
+    let a = old_only(x);
+    let b = if x > 0 { 1 } else if x > 10 { 2 } else { 3 };
+    let c = if x > 3 { 4 } else { 5 };
+    if x > 5 {
@@ -27 +24 @@
-    while !on_new() {
+    loop {
@@ -30,5 +27 @@
-    while i < n && on_new() {
-        t += i;
-        i += 1;
-    }
-    if traced(shared(1)) && !on_new() {
+    if traced(shared(1)) {
@@ -38,3 +31,2 @@
-        0 if on_new() => t,
-        1 if !on_new() => old_only(t),
-        _ => 2 * (if on_new() { t + 1 } else { t }),
+        1 => old_only(t),
+        _ => 2 * t,
note rewrite.imports: removed 2 imports the fold left unused
note refactor.unused: 2 items have no use left in the program: crate::flags::on_new (flags.vl:2:8), crate::flags::new_step (flags.vl:6:8)
try: volec edit delete crate::flags::on_new
try: volec edit delete crate::flags::new_step
## A call whose arguments call functions is left (they would no longer
## run). The edit is checked as any is: a function that is no predicate.
$ refactor fold traced --as true --dry-run
warning refactor.fold: 1 call of crate::flags::traced is left: its arguments call functions, which the constant would not; first: main.vl:34:8
note refactor.fold: crate::flags::traced has no call to fold
$ refactor fold new_step --as true
main.vl:7:16: error[type error] expected 'i64', got 'bool'  [edited: crate::step]
note rewrite.imports: removed 1 import the fold left unused
note refactor.unused: 1 item has no use left in the program: crate::flags::new_step (flags.vl:6:8)
try: volec edit delete crate::flags::new_step
error edit.breaks: 1 new error; nothing written; the error: main.vl:7:16: expected 'i64', got 'bool'
try: volec refactor fold new_step --as true --no-check
[exit 1]
$ refactor fold on_new
error refactor.usage: a function NAME and the value its calls have now: --as true, --as false
try: volec refactor fold NAME --as true --dry-run
[exit 2]
$ refactor fold on_new --as maybe
error refactor.usage: --as takes true or false
try: volec refactor fold NAME --as true --dry-run
[exit 2]
$ refactor fold nope --as true
error query.no-match: no definition 'nope'
try: volec refactor fold std::cli::Names::none
try: volec refactor fold std::collections::btree_map::BCursor.node
try: volec refactor fold std::collections::btree_map::BTreeOccupiedEntry.node
[exit 1]
