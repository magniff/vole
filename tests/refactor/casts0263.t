## 0.26.3: `fix --only casts` (tests/refactor/casts0263/): a usize's `as
## i64` goes where the value means the same as a usize, one function per
## class (an index, a slicing and a slicing to its own end, comparisons, a
## counted loop, lets) and stays in each refused one (a subtraction, other
## arithmetic, a stored i64, an argument, a comparison with an i64 counter,
## a sign test, a counter or local that reaches arithmetic, a `var`, a
## typed let, a closure). `casts-list` lists each cast without writing; the
## program prints the same before and after, and a second run finds
## nothing to do.
% volec main.vl -o before >/dev/null && ./before 2>&1
100 3 true
3 true true
-1 14 2
8 1
ok: built before
$ fix --only casts-list
main.vl:10	index	index	b.len as i64
main.vl:15	slice-end	slice-end	a.len as i64
main.vl:16	index	index	tail.len as i64
main.vl:17	arith	arith	head.len as i64
main.vl:22	compare	compare	a.len as i64
main.vl:22	compare	compare	b.len as i64
main.vl:22	compare	compare	a.len as i64
main.vl:28	loop	loop	s.len as i64
main.vl:29	compare	compare	s.len as i64
main.vl:38	refused	let	s.len as i64
main.vl:44	let	let	s.len as i64
main.vl:45	compare	compare	t.len as i64
main.vl:50	sub	sub	s.len as i64
main.vl:56	loop	loop	v.len() as i64
main.vl:57	stored	stored	v[k].len as i64
main.vl:59	arith	arith	v.len() as i64
main.vl:59	stored	stored	v.len() as i64
main.vl:69	cmp-i64	cmp-i64	s.len as i64
main.vl:72	cmp-i64	cmp-i64	s.len as i64
main.vl:78	refused	loop	s.len as i64
main.vl:81	stored	stored	s.len as i64
main.vl:83	stored	stored	s.len as i64
main.vl:89	copied	cmp-i64	w.len as i64
main.vl:89	copied	cmp-i64	s.len as i64
main.vl:89	copied	copied	v.iter().filter(|w| w.len as i64 < s.len as i64).count() as i64
--- a/main.vl
+++ b/main.vl
@@ -10 +10 @@
-    a[b.len as i64]
+    a[b.len]
@@ -15,2 +15,2 @@
-    let tail = a[i..a.len as i64];
-    let head = a[1..tail.len as i64];
+    let tail = a[i..];
+    let head = a[1..tail.len];
@@ -22 +22 @@
-    a.len as i64 == b.len as i64 && a.len as i64 > 2
+    a.len == b.len && a.len > 2
@@ -28,2 +28,2 @@
-    for i in 0..s.len as i64 {
-        if s[i] == c && i < s.len as i64 {
+    for i in 0..s.len {
+        if s[i] == c && i < s.len {
@@ -44,2 +44,2 @@
-    let n = s.len as i64;
-    n > t.len as i64
+    let n = s.len;
+    n > t.len
@@ -56 +56 @@
-    for k in 0..v.len() as i64 {
+    for k in 0..v.len() {
note fix.casts: usize to i64 casts: removed index 2 slice-end 1 compare 5 loop 2 let 1; kept sub 1 arith 2 cmp-i64 2 stored 4 other 0 refused 2 copied 3; other casts to i64 noop 0 not-usize 0
$ fix --only casts
fixed 11 usize casts	main.vl	+9 -9 lines
note fix.casts: usize to i64 casts: removed index 2 slice-end 1 compare 5 loop 2 let 1; kept sub 1 arith 2 cmp-i64 2 stored 4 other 0 refused 2 copied 3; other casts to i64 noop 0 not-usize 0
% cat main.vl
// `volec fix --only casts` (0.26.3, tests/refactor/casts0263.t): a usize's
// `as i64` goes where the value means the same as a usize (an index, a
// slicing, a comparison with a usize, a counted loop's bound, a `let` used
// only so), and stays everywhere else. Each function is one case; the
// program prints the same before and after.
use std::{Gpa, Vec};

// (removed) an index
fn index(a: [u8], b: [u8]) -> u8 {
    a[b.len]
}

// (removed) slicing: to a's own end (`a[i..]`), and with a literal start
fn slice(a: [u8], i: i64) -> i64 {
    let tail = a[i..];
    let head = a[1..tail.len];
    head.len as i64 + 0
}

// (removed) comparisons with another length and with a literal
fn compare(a: [u8], b: [u8]) -> bool {
    a.len == b.len && a.len > 2
}

// (removed) a counted loop whose counter is an index and a comparison
fn count(s: [u8], c: u8) -> i64 {
    var n = 0;
    for i in 0..s.len {
        if s[i] == c && i < s.len {
            n += 1;
        }
    }
    n
}

// (kept) a let that reaches a subtraction (`s[n - 1]`): refused
fn last_is(s: [u8], c: u8) -> bool {
    let n = s.len as i64;
    n > 0 && s[n - 1] == c
}

// (removed) a let used in comparisons only
fn longer(s: [u8], t: [u8]) -> bool {
    let n = s.len;
    n > t.len
}

// (kept) a subtraction, which may go below 0
fn before_last(s: [u8]) -> i64 {
    s.len as i64 - 2
}

// (kept) other arithmetic, a stored i64, an argument
fn widths(v: Vec<[u8], Gpa>) -> i64 {
    var total = 0;
    for k in 0..v.len() {
        total += v[k].len as i64;
    }
    total + v.len() as i64 * 2 + double(v.len() as i64)
}

fn double(x: i64) -> i64 {
    x * 2
}

// (kept) compared with an i64 counter, and by its sign
fn skip_blanks(s: [u8]) -> i64 {
    var i = 0;
    while i < s.len as i64 && s[i] == ' ' {
        i += 1;
    }
    if s.len as i64 >= 0 { i } else { -1 }
}

// (kept) a counter that reaches arithmetic, a var, a typed let
fn refused(s: [u8]) -> i64 {
    var sum = 0;
    for i in 0..s.len as i64 {
        sum += i;
    }
    var m = s.len as i64;
    m -= 1;
    let t: i64 = s.len as i64;
    sum + m + t
}

// (kept) a value a closure reaches
fn shorter(v: Vec<[u8], Gpa>, s: [u8]) -> i64 {
    v.iter().filter(|w| w.len as i64 < s.len as i64).count() as i64
}

fn main(gpa: Gpa) {
    var v: Vec<[u8], Gpa> = Vec::new_in(gpa);
    v.push("ab");
    v.push("vole");
    println("{} {} {}", index("abcdef", "abc"), slice("abcdef", 2), compare("abc", "xyz"));
    println("{} {} {}", count("banana", 'a'), last_is("vole", 'e'), longer("vole", "ab"));
    println("{} {} {}", before_last("x"), widths(v), skip_blanks("  x"));
    println("{} {}", refused("abc"), shorter(v, "abc"));
}
% volec main.vl -o after >/dev/null && ./after 2>&1
100 3 true
3 true true
-1 14 2
8 1
ok: built after
$ fix --only casts
note fix.casts: usize to i64 casts: removed index 0 slice-end 0 compare 0 loop 0 let 0; kept sub 1 arith 2 cmp-i64 2 stored 4 other 0 refused 2 copied 3; other casts to i64 noop 0 not-usize 0
note fix.none: nothing to fix
