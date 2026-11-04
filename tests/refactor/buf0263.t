## 0.26.3: `fix --only buf` (tests/refactor/buf0263/): each Buf binding
## by the evidence of its writes. Text, to String<Gpa>: a push_str of a
## str (greet's result), a format write (t), constant bytes below 0x80
## (a), a field's (Log.lines). Bytes, to Vec<u8, Gpa>: a constant at or
## above 0x80 (hi), a push_str of a [u8] and a non-constant byte through
## a parameter (r, put's out). Refused, each named: mixed (m), passed to
## std where it takes a Buf (f), text with a method String lacks (c,
## take), no write (e). The method table is
## printed; the refusals make the exit 1. The program prints the same.
% volec main.vl -o before >/dev/null && ./before 2>&1
hello
1 + 2 = 3
ok
1
4
started
from_buf
taken
2
ok: built before
$ fix --only buf --dry-run
--- a/main.vl
+++ b/main.vl
@@ -4 +4 @@
-    lines: Buf<A>,
+    lines: String<A>,
@@ -9,2 +9,2 @@
-fn greet(gpa: Gpa) -> Buf<Gpa> {
-    var b = Buf::new_in(gpa);
+fn greet(gpa: Gpa) -> String<Gpa> {
+    var b = String::new_in(gpa);
@@ -16 +16 @@
-fn put(out: inout Buf<Gpa>, x: u8) {
+fn put(out: inout Vec<u8, Gpa>, x: u8) {
@@ -22 +22 @@
-    var t = Buf::new_in(gpa);
+    var t = String::new_in(gpa);
@@ -25 +25 @@
-    var a = Buf::new_in(gpa);
+    var a = String::new_in(gpa);
@@ -29 +29 @@
-    var hi = Buf::new_in(gpa);
+    var hi = Vec::<u8, Gpa>::new_in(gpa);
@@ -33,2 +33,2 @@
-    var r = Buf::new_in(gpa);
-    r.push_str(raw);
+    var r = Vec::<u8, Gpa>::new_in(gpa);
+    r.extend_from_slice(raw);
@@ -37 +37 @@
-    var log = Log { lines: Buf::new_in(gpa), count: 0 };
+    var log = Log { lines: String::new_in(gpa), count: 0 };
note fix.buf-refused: 'm' at main.vl:41:9: mixed: text (push_str of a str at main.vl:42:5) and bytes (push of a byte that is not a constant at main.vl:44:5)
note fix.buf-refused: 'f' at main.vl:46:9: passed to std's 'String<Gpa>::from_buf' at main.vl:48:31, which takes a Buf
note fix.buf-refused: 'c' at main.vl:50:9: text, but its 'take' at main.vl:51:17 has no String<A> form
note fix.buf-refused: 'taken' at main.vl:51:9: no write says text or bytes
note fix.buf-refused: 'e' at main.vl:53:9: no write says text or bytes
note fix.buf-table: Buf's methods, as String<A> (text) and Vec<u8, A> (bytes); '-': none, the binding is refused
  new_in -> String::new_in | Vec::<u8>::new_in
  with_capacity_in -> String::with_capacity_in | Vec::<u8>::with_capacity_in
  from_in -> String::from_in | -
  len -> len | len
  push -> push | push
  push_str -> push_str | extend_from_slice
  push_fmt -> push_fmt | -
  push_int -> push_fmt | -
  push_cstr -> - | -
  as_slice -> as_slice | as_slice
  as_mut_slice -> - | as_mut_slice
  clear -> clear | clear
  free -> clear | free
  take -> - | take
  capacity -> capacity | capacity
  reserve -> reserve | reserve
  allocator -> allocator | allocator
  clone -> clone | clone
[exit 1]
$ fix --only buf
fixed 10 Buf sites	main.vl	+10 -10 lines
note fix.buf-refused: 'm' at main.vl:41:9: mixed: text (push_str of a str at main.vl:42:5) and bytes (push of a byte that is not a constant at main.vl:44:5)
note fix.buf-refused: 'f' at main.vl:46:9: passed to std's 'String<Gpa>::from_buf' at main.vl:48:31, which takes a Buf
note fix.buf-refused: 'c' at main.vl:50:9: text, but its 'take' at main.vl:51:17 has no String<A> form
note fix.buf-refused: 'taken' at main.vl:51:9: no write says text or bytes
note fix.buf-refused: 'e' at main.vl:53:9: no write says text or bytes
note fix.buf-table: Buf's methods, as String<A> (text) and Vec<u8, A> (bytes); '-': none, the binding is refused
  new_in -> String::new_in | Vec::<u8>::new_in
  with_capacity_in -> String::with_capacity_in | Vec::<u8>::with_capacity_in
  from_in -> String::from_in | -
  len -> len | len
  push -> push | push
  push_str -> push_str | extend_from_slice
  push_fmt -> push_fmt | -
  push_int -> push_fmt | -
  push_cstr -> - | -
  as_slice -> as_slice | as_slice
  as_mut_slice -> - | as_mut_slice
  clear -> clear | clear
  free -> clear | free
  take -> - | take
  capacity -> capacity | capacity
  reserve -> reserve | reserve
  allocator -> allocator | allocator
  clone -> clone | clone
[exit 1]
$ check
ok: 0 errors in main.vl
% volec main.vl -o after >/dev/null && ./after 2>&1
hello
1 + 2 = 3
ok
1
4
started
from_buf
taken
2
ok: built after
$ explain fix.buf-refused
fix.buf-refused: note, exit 1
(0.26.3) `fix --only buf` left a std `Buf` binding as it is: a local, a parameter, a field or a result, with the bindings its value flows between. It writes `String<A>` only when every write says text (a push_str of a str, a format write, a constant byte below 0x80) and `Vec<u8, A>` only when every write says bytes (a non-constant byte, a constant at or above 0x80, a push_str of a [u8]). Refused: writes on both sides (mixed), no write at all, a binding passed to a std function that takes a Buf, and a method that has no form on the side decided (fix.buf-table).
fix: Write the type by hand: `String<A>` for text, `Vec<u8, A>` for bytes (a push of 0xC3 is one byte in a Vec, two in a String, which pushes a code point). The note names the writes on each side.
example:
    note fix.buf-refused: 'm' at main.vl:41:9: mixed: text (push_str of a str at main.vl:42:5) and bytes (push of a byte that is not a constant at main.vl:44:5)
$ explain fix.buf-table
fix.buf-table: note
(0.26.3) The table `fix --only buf` maps Buf's methods through: each method, its String<A> form and its Vec<u8, A> form (`push_str` is `extend_from_slice` on a Vec; `-`: none, and a binding that calls it on that side is refused).
fix: Nothing to do: it is printed with every run, so a reader knows what each call became.
example:
    note fix.buf-table: Buf's methods, as String<A> (text) and Vec<u8, A> (bytes); '-': none, the binding is refused
