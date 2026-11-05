## 0.26.5: `fix --only statics` (tests/refactor/statics0265/), what the
## 0.26.4 phases did by hand. --prune: the group without the statics that
## reach a function no owner gives the context (LAST: `peek`, a function
## value), or one outside the prefixes. first.group: the `use` lines
## added (`use`: where a function takes the context; `owner-use`: where
## an owner makes it), the statics' imports taken out, their declarations
## deleted; a static in a format literal's hole (`{count}` and the named
## argument `count = cx.count`); named arguments (the context named, in
## its parameter's place); a static lent beside the context (`&TOTAL`:
## taken into a local, put back after; `&PAIR[0]` as a raw pointer, which
## reaches PAIR[1] too: the whole static taken, the run's 29 kept). second.group: a context given
## before (the owner's local kept, a `cx: Cx` made inout where it now
## changes the context, its calls given `&cx`).
% volec main.vl -o before >/dev/null && ./before 2>&1
count 3, names 1
29
ok: built before
$ fix --only statics-list --group prune.group --prune crate
param cx
type Cx
init cx_new()
owner run
static crate::tab::COUNT count
static crate::tab::TOTAL total
static crate::tab::PAIR pair
# dropped static crate::tab::LAST last	(reaches peek)
note fix.statics: pruned in 2 rounds: 3 of 4 statics kept
$ fix --only statics-list --group prune.group --prune crate::tab
param cx
type Cx
init cx_new()
owner run
# dropped static crate::tab::COUNT count	(reaches show)
static crate::tab::TOTAL total
static crate::tab::PAIR pair
# dropped static crate::tab::LAST last	(reaches peek)
note fix.statics: pruned in 2 rounds: 2 of 4 statics kept
$ fix --only statics --group first.group
fixed	2 files	+28 -25 lines
note fix.statics: statics 3; functions using them 4, given the parameter 5 (inout 3), owners 1; edits: uses 9, calls 8, parameters 5, statements given their arguments as lets 0; declarations deleted 3, imports taken out 3, use lines added 3; format arguments for holes 1; lent beside the context: taken into locals 2, left 0
% git diff
diff --git a/main.vl b/main.vl
index 96a09e8..b11a239 100644
--- a/main.vl
+++ b/main.vl
@@ -5,13 +5,14 @@
 mod ctx;
 mod tab;
 
-use crate::tab::{COUNT, LAST, NAMES, PAIR, TOTAL, bump};
+use crate::ctx::{Cx, cx_new};
+use crate::tab::{LAST, NAMES, bump};
 
 // (a static in a format literal's hole)
-fn show() -> i64 {
-    NAMES.push(COUNT);
-    println("count {COUNT}, names {}", names_len());
-    COUNT
+fn show(cx: Cx) -> i64 {
+    NAMES.push(cx.count);
+    println("count {count}, names {}", names_len(), count = cx.count);
+    cx.count
 }
 
 fn names_len() -> i64 {
@@ -19,26 +20,26 @@ fn names_len() -> i64 {
 }
 
 // (named arguments: the context named, in its parameter's place)
-fn put(a: i64, k: i64, by: i64 = 2) -> i64 {
-    a * by + k + COUNT
+fn put(a: i64, k: i64, cx: Cx, by: i64 = 2) -> i64 {
+    a * by + k + cx.count
 }
 
 // (lent a static of the group beside the context)
-fn add_to(n: i64, x: inout i64) {
+fn add_to(n: i64, x: inout i64, cx: inout Cx) {
     x += n;
-    bump();
+    bump(&cx);
 }
 
 // (lent an element as a raw pointer, which reaches the next one too: the
 // whole static is taken into the local)
-fn add_pair(n: i64, m: *i64) {
+fn add_pair(n: i64, m: *i64, cx: inout Cx) {
     // UNSAFE: m is a raw pointer to two counts.
     // SAFETY: the callers give an element with one after it.
     unsafe {
         m[0] += n;
         m[1] += n * 2;
     }
-    bump();
+    bump(&cx);
 }
 
 fn peek() -> i64 {
@@ -51,13 +52,18 @@ fn apply(f: fn() -> i64) -> i64 {
 
 // (the owner)
 fn run() -> i64 {
-    bump();
-    add_to(5, &TOTAL);
-    add_pair(3, &PAIR[0]);
-    let a = put(1, k: 2);
-    let b = put(1, k: 2, by: 3);
-    let s = show();
-    a + b + s + TOTAL + PAIR[1] + apply(peek)
+    var cx = cx_new();
+    bump(&cx);
+    var cx_total = cx.total;
+    add_to(5, &cx_total, &cx);
+    cx.total = cx_total;
+    var cx_pair = cx.pair;
+    add_pair(3, &cx_pair[0], &cx);
+    cx.pair = cx_pair;
+    let a = put(1, k: 2, cx: cx);
+    let b = put(1, k: 2, cx: cx, by: 3);
+    let s = show(cx);
+    a + b + s + cx.total + cx.pair[1] + apply(peek)
 }
 
 fn main() -> i32 {
diff --git a/tab.vl b/tab.vl
index e450b2d..79838c5 100644
--- a/tab.vl
+++ b/tab.vl
@@ -1,5 +1,7 @@
 // The statics the groups move (tests/refactor/statics0265.t).
 
+use crate::ctx::Cx;
+
 pub struct Tab {
     pub a: [i64; 8],
     pub n: i64,
@@ -16,17 +18,12 @@ impl Tab {
     }
 }
 
-// (moved by first.group)
-pub static var COUNT: i64 = 0;
-pub static var TOTAL: i64 = 0;
-pub static var PAIR: [i64; 2] = [0, 0];
-
 // (moved by second.group, into the context first.group gave)
 pub static var NAMES: Tab = Tab { a: [0; 8], n: 0 };
 
 // (read by a function used as a value: --prune leaves it out)
 pub static var LAST: i64 = 0;
 
-pub fn bump() {
-    COUNT += 1;
+pub fn bump(cx: inout Cx) {
+    cx.count += 1;
 }
% volec main.vl -o after >/dev/null && ./after 2>&1
count 3, names 1
29
ok: built after
$ fix --only statics --group second.group
fixed	2 files	+7 -10 lines
note fix.statics: statics 1; functions using them 2, given the parameter 1 (inout 0), owners 0; edits: uses 2, calls 2, parameters 2, statements given their arguments as lets 0; declarations deleted 1, imports taken out 1, use lines added 0
% git diff -- main.vl tab.vl | tail -n +1
diff --git a/main.vl b/main.vl
index 96a09e8..8a2db0a 100644
--- a/main.vl
+++ b/main.vl
@@ -5,40 +5,41 @@
 mod ctx;
 mod tab;
 
-use crate::tab::{COUNT, LAST, NAMES, PAIR, TOTAL, bump};
+use crate::ctx::{Cx, cx_new};
+use crate::tab::{LAST, bump};
 
 // (a static in a format literal's hole)
-fn show() -> i64 {
-    NAMES.push(COUNT);
-    println("count {COUNT}, names {}", names_len());
-    COUNT
+fn show(cx: inout Cx) -> i64 {
+    cx.names.push(cx.count);
+    println("count {count}, names {}", names_len(cx), count = cx.count);
+    cx.count
 }
 
-fn names_len() -> i64 {
-    NAMES.len()
+fn names_len(cx: Cx) -> i64 {
+    cx.names.len()
 }
 
 // (named arguments: the context named, in its parameter's place)
-fn put(a: i64, k: i64, by: i64 = 2) -> i64 {
-    a * by + k + COUNT
+fn put(a: i64, k: i64, cx: Cx, by: i64 = 2) -> i64 {
+    a * by + k + cx.count
 }
 
 // (lent a static of the group beside the context)
-fn add_to(n: i64, x: inout i64) {
+fn add_to(n: i64, x: inout i64, cx: inout Cx) {
     x += n;
-    bump();
+    bump(&cx);
 }
 
 // (lent an element as a raw pointer, which reaches the next one too: the
 // whole static is taken into the local)
-fn add_pair(n: i64, m: *i64) {
+fn add_pair(n: i64, m: *i64, cx: inout Cx) {
     // UNSAFE: m is a raw pointer to two counts.
     // SAFETY: the callers give an element with one after it.
     unsafe {
         m[0] += n;
         m[1] += n * 2;
     }
-    bump();
+    bump(&cx);
 }
 
 fn peek() -> i64 {
@@ -51,13 +52,18 @@ fn apply(f: fn() -> i64) -> i64 {
 
 // (the owner)
 fn run() -> i64 {
-    bump();
-    add_to(5, &TOTAL);
-    add_pair(3, &PAIR[0]);
-    let a = put(1, k: 2);
-    let b = put(1, k: 2, by: 3);
-    let s = show();
-    a + b + s + TOTAL + PAIR[1] + apply(peek)
+    var cx = cx_new();
+    bump(&cx);
+    var cx_total = cx.total;
+    add_to(5, &cx_total, &cx);
+    cx.total = cx_total;
+    var cx_pair = cx.pair;
+    add_pair(3, &cx_pair[0], &cx);
+    cx.pair = cx_pair;
+    let a = put(1, k: 2, cx: cx);
+    let b = put(1, k: 2, cx: cx, by: 3);
+    let s = show(&cx);
+    a + b + s + cx.total + cx.pair[1] + apply(peek)
 }
 
 fn main() -> i32 {
diff --git a/tab.vl b/tab.vl
index e450b2d..4564979 100644
--- a/tab.vl
+++ b/tab.vl
@@ -1,5 +1,7 @@
 // The statics the groups move (tests/refactor/statics0265.t).
 
+use crate::ctx::Cx;
+
 pub struct Tab {
     pub a: [i64; 8],
     pub n: i64,
@@ -16,17 +18,9 @@ impl Tab {
     }
 }
 
-// (moved by first.group)
-pub static var COUNT: i64 = 0;
-pub static var TOTAL: i64 = 0;
-pub static var PAIR: [i64; 2] = [0, 0];
-
-// (moved by second.group, into the context first.group gave)
-pub static var NAMES: Tab = Tab { a: [0; 8], n: 0 };
-
 // (read by a function used as a value: --prune leaves it out)
 pub static var LAST: i64 = 0;
 
-pub fn bump() {
-    COUNT += 1;
+pub fn bump(cx: inout Cx) {
+    cx.count += 1;
 }
% volec main.vl -o again >/dev/null && ./again 2>&1
count 3, names 1
29
ok: built again
$ fix --only statics --group second.group
note fix.statics: statics 0; functions using them 0, given the parameter 0 (inout 0), owners 0; edits: uses 0, calls 0, parameters 0, statements given their arguments as lets 0
note fix.none: nothing to fix
