## (0.29) A slice has no fields (F30.4): `s.len` and `s.ptr`, vole's
## spellings until 0.28, are errors that name the method, each with its
## exact fix, and `fix --suggested` writes `len()` and `as_ptr()` at
## every one in one checked edit. A rewrite that
## would write the field back is refused by its check.
$ check
main.vl:4:15: error[type error] a slice has no field 'len' | help: call its method: '.len()' | try: volec fix --suggested main.vl
main.vl:12:5: error[type error] a slice has no field 'ptr' | help: call its method: '.as_ptr()' ('.as_mut_ptr()' for a '*mut T') | try: volec fix --suggested main.vl
main.vl:12:14: error[type error] a slice has no field 'ptr' | help: call its method: '.as_ptr()' ('.as_mut_ptr()' for a '*mut T') | try: volec fix --suggested main.vl
main.vl:12:34: error[type error] a slice has no field 'len' | help: call its method: '.len()' | try: volec fix --suggested main.vl
main.vl:18:69: error[type error] a slice has no field 'len' | help: call its method: '.len()' | try: volec fix --suggested main.vl
[exit 1]
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -4 +4 @@
-    while i < s.len {
+    while i < s.len() {
@@ -12 +12 @@
-    a.ptr == b.as_bytes().ptr && a.len == b.len()
+    a.as_ptr() == b.as_bytes().as_ptr() && a.len() == b.len()
@@ -18 +18 @@
-    println("{} {} {}", total(&v[..]), same(text.as_bytes(), text), v[1..].len);
+    println("{} {} {}", total(&v[..]), same(text.as_bytes(), text), v[1..].len());
$ fix --suggested
fixed 5 suggested fixes	main.vl	+3 -3 lines
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
$ rewrite '$s.len()' '$s.len' --where '$s: &[i64]'
main.vl:4:15: error[type error] a slice has no field 'len' | help: call its method: '.len()' | try: volec fix --suggested main.vl  [edited: crate::total]
main.vl:18:69: error[type error] a slice has no field 'len' | help: call its method: '.len()' | try: volec fix --suggested main.vl  [edited: crate::main]
note rewrite.types: 2 sites match but for --where; first: $s is &[u8] at main.vl:12:44
try: volec rewrite '$s.len()' '$s.len' --where '$s: &[u8]' --dry-run
error edit.breaks: 2 new errors; nothing written; the first: main.vl:4:15: a slice has no field 'len'
try: volec rewrite '$s.len()' '$s.len' --where '$s: &[i64]' --no-check
[exit 1]
% cat main.vl
fn total(s: &[i64]) -> i64 {
    let mut t = 0;
    let mut i = 0;
    while i < s.len() {
        t += s[i];
        i += 1;
    }
    t
}

fn same(a: &[u8], b: &str) -> bool {
    a.as_ptr() == b.as_bytes().as_ptr() && a.len() == b.len()
}

fn main() {
    let v = [4i64, 5, 6];
    let text = "abc";
    println("{} {} {}", total(&v[..]), same(text.as_bytes(), text), v[1..].len());
}
% volec main.vl -o prog >/dev/null && ./prog
15 true 2
ok: built prog
