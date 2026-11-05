## 0.26.5: `fix --only statics` with views (tests/refactor/statics0265v/):
## a `view PATH EXPR` line names a function that gives its calls the
## context as EXPR, let (a thread's task loop reaching it through a
## pointer). One whose callee changes the context is refused
## (refused-view), and --prune leaves out what that callee writes (COUNT).
% volec main.vl -o before >/dev/null && ./before 2>&1
19
ok: built before
$ fix --only statics-list --group view.group
main.vl:20	let	total_len	uses total
main.vl:24	inout	bump	writes at 25 COUNT += 1	uses count
main.vl:30	view	tick
main.vl:38	refused-view	tock
main.vl:49	owner	run
error fix.statics: 'tock' needs the group's context, and no owner gives it (refused-view): nothing is changed
  help: name an owner above it in the group file, or leave out the statics that reach it (--prune)
  try: volec fix --only statics-list --group view.group
note fix.statics: statics 2; functions using them 2, given the parameter 2 (inout 1), owners 0; edits: uses 0, calls 0, parameters 0, statements given their arguments as lets 0
[exit 1]
$ fix --only statics-list --group view.group --prune crate
param cx
type Cx
init cx_new()
owner run
view tick *(VIEW as *Cx)
view tock *(VIEW as *Cx)
# dropped static COUNT count	(reaches tock)
static TOTAL total
note fix.statics: pruned in 2 rounds: 1 of 2 statics kept
% volec fix --only statics-list --group view.group --prune crate 2>/dev/null > pruned.group
$ fix --only statics --group pruned.group
fixed	main.vl	+5 -5 lines
note fix.statics: statics 1; functions using them 1, given the parameter 1 (inout 0), owners 1; edits: uses 1, calls 2, parameters 1, statements given their arguments as lets 0; declarations deleted 1, imports taken out 0, use lines added 0
% sed -i.bak 's/^    var cx = cx_new();$/    var cx = cx_new();\n    unsafe {\n        VIEW = \&cx as *Cx as *u8;\n    }/' main.vl && rm main.vl.bak && git diff
diff --git a/main.vl b/main.vl
index 6b4f9dc..a91c683 100644
--- a/main.vl
+++ b/main.vl
@@ -12,13 +12,12 @@ pub fn cx_new() -> Cx {
 }
 
 static var COUNT: i64 = 0;
-static var TOTAL: i64 = 7;
 
 // (the context's address, as C's void *)
 static var VIEW: *u8 = 0 as *u8;
 
-fn total_len() -> i64 {
-    TOTAL + 1
+fn total_len(cx: Cx) -> i64 {
+    cx.total + 1
 }
 
 fn bump() -> i64 {
@@ -30,7 +29,7 @@ fn bump() -> i64 {
 fn tick() -> i64 {
     // UNSAFE: the context is reached through VIEW.
     // SAFETY: VIEW is the owner's context, alive while apply runs.
-    unsafe { total_len() }
+    unsafe { total_len(*(VIEW as *Cx)) }
 }
 
 // (a view whose callee changes the context: refused; --prune leaves out
@@ -47,7 +46,11 @@ fn apply(f: fn() -> i64) -> i64 {
 
 // (the owner)
 fn run() -> i64 {
-    apply(tick) + apply(tock) + total_len() + bump()
+    var cx = cx_new();
+    unsafe {
+        VIEW = &cx as *Cx as *u8;
+    }
+    apply(tick) + apply(tock) + total_len(cx) + bump()
 }
 
 fn main() -> i32 {
% volec main.vl -o after >/dev/null && ./after 2>&1
19
ok: built after
