## 0.26.4: `fix --only statics --group FILE` (tests/refactor/statics0264/):
## a group of statics moved into a context passed down (body.group: the
## statics TABLE, COUNT and LABEL into `Body`, made by the owner `run`).
## Each function naming one, and its callers up to the owner, takes the
## context last (before a parameter with a default): inout where it or a
## callee writes it (an assignment, a method of it, `&X`), let otherwise;
## each use becomes `body.field`, each call gives `&body` or `body`, a
## named argument stays last; a method of the context's field given an
## argument that changes the context gets it as a `let` before the statement. The list mode is a dry run; a second run
## changes nothing, and the program prints the same. Without an owner
## (noowner.group) the callers reach `main`, which nothing calls: refused,
## nothing changed.
$ fix --only statics --group noowner.group
error fix.statics: 'main' needs the group's context, and no owner gives it (refused-entry): nothing is changed
  help: name an owner above it in the group file
  try: volec fix --only statics-list --group noowner.group
note fix.statics: statics 3; functions using them 4, given the parameter 9 (inout 5), owners 0; edits: uses 0, calls 0, parameters 0, statements given their arguments as lets 0
[exit 1]
% volec main.vl -o before >/dev/null && ./before 2>&1
60
ok: built before
$ fix --only statics-list --group body.group
main.vl:36	let	total
main.vl:45	inout	add	writes at 46 push
main.vl:52	inout	two
main.vl:58	inout	again	writes at 59 push
main.vl:64	let	scaled
main.vl:69	let	label_len
main.vl:79	let	Probe::look
main.vl:85	owner	run
--- a/main.vl
+++ b/main.vl
@@ -36 +36 @@
-fn total() -> i64 {
+fn total(body: Body) -> i64 {
@@ -38,2 +38,2 @@
-    for i in 0..TABLE.len() {
-        s += TABLE.a[i];
+    for i in 0..body.table.len() {
+        s += body.table.a[i];
@@ -41 +41 @@
-    s + COUNT
+    s + body.count
@@ -45,4 +45,4 @@
-fn add(x: i64) -> i64 {
-    TABLE.push(x);
-    COUNT += 1;
-    TABLE.len()
+fn add(x: i64, body: inout Body) -> i64 {
+    body.table.push(x);
+    body.count += 1;
+    body.table.len()
@@ -52,2 +52,2 @@
-fn two(a: i64, b: i64) -> i64 {
-    a + add(add(b) + a)
+fn two(a: i64, b: i64, body: inout Body) -> i64 {
+    a + add(add(b, &body) + a, &body)
@@ -58,3 +58,4 @@
-fn again(x: i64) -> i64 {
-    TABLE.push(add(x));
-    COUNT
+fn again(x: i64, body: inout Body) -> i64 {
+    let body_arg = add(x, &body);
+    body.table.push(body_arg);
+    body.count
@@ -64,2 +65,2 @@
-fn scaled(x: i64, by: i64 = 2) -> i64 {
-    (x + total()) * by
+fn scaled(x: i64, body: Body, by: i64 = 2) -> i64 {
+    (x + total(body)) * by
@@ -69,2 +70,2 @@
-fn label_len() -> i64 {
-    LABEL.len() as i64
+fn label_len(body: Body) -> i64 {
+    body.label.len() as i64
@@ -79,2 +80,2 @@
-    fn look(self) -> i64 {
-        self.k + total()
+    fn look(self, body: Body) -> i64 {
+        self.k + total(body)
@@ -86,3 +87,4 @@
-    let a = two(1, 2);
-    let b = scaled(1);
-    let c = scaled(1, by: 3);
+    var body = body_new();
+    let a = two(1, 2, &body);
+    let b = scaled(1, body);
+    let c = scaled(1, body, by: 3);
@@ -90,2 +92,2 @@
-    let d = again(4);
-    a + b + c + d + p.look() + label_len()
+    let d = again(4, &body);
+    a + b + c + d + p.look(body) + label_len(body)
note fix.statics: statics 3; functions using them 4, given the parameter 7 (inout 3), owners 1; edits: uses 9, calls 11, parameters 7, statements given their arguments as lets 1
$ fix --only statics --group body.group
fixed	main.vl	+26 -24 lines
note fix.statics: statics 3; functions using them 4, given the parameter 7 (inout 3), owners 1; edits: uses 9, calls 11, parameters 7, statements given their arguments as lets 1
% sed -n 56,62p main.vl
// (a method of the table given an argument that changes the context:
// the argument becomes a `let` before the statement)
fn again(x: i64, body: inout Body) -> i64 {
    let body_arg = add(x, &body);
    body.table.push(body_arg);
    body.count
}
% volec main.vl -o after >/dev/null && ./after 2>&1
60
ok: built after
$ fix --only statics --group body.group
note fix.statics: statics 3; functions using them 0, given the parameter 0 (inout 0), owners 0; edits: uses 0, calls 0, parameters 0, statements given their arguments as lets 0
note fix.none: nothing to fix
