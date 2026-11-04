## 0.26.3: `fix --only buf` (tests/refactor/buf0263/): each Buf binding
## by the evidence of its writes. Text, to String<Gpa>: a push_str of a
## str (greet's result), a format write (t, an enum variant's field
## through Msg::Text and its pattern), constant bytes below 0x80 (a), a
## field's (Log.lines). Bytes, to Vec<u8, Gpa>: a constant at or above
## 0x80 (hi), a push_str of a [u8] and a non-constant byte through a
## parameter (r, put's out), a str and a byte together (weak text gives
## way: p, with a [u8] constant and an index), an Option's Buf and the
## pattern that takes it (first_word's w), a closure's capture (cap), no
## write (e), a format write and a byte (fb: format_in's bytes). Refused,
## each named: written through a by-value parameter (more's b, and lp
## with it), mixed (m: printed as text, and a byte),
## passed to std where it takes a Buf (f), text with a method String
## lacks (c, take). The method table is printed; the refusals make the
## exit 1. The program prints the same.
% volec main.vl -o before >/dev/null && ./before 2>&1
hello
1 + 2 = 3
7!
ok
1
4
started
Dir/head;
42
v
5
from_buf
taken
2
[a	]
main.vl:4:12: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:9:10: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:16:23: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:17:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:23:19: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:28:44: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:32:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:39:12: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:49:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:52:14: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:56:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:60:14: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:64:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:68:28: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:72:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:78:14: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:82:15: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:86:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:91:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:95:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:98:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:99:14: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
ok: built before
$ fix --only buf --dry-run
--- a/main.vl
+++ b/main.vl
@@ -4 +4 @@
-    lines: Buf<A>,
+    lines: String<A>,
@@ -9 +9 @@
-    Text(Buf<A>),
+    Text(String<A>),
@@ -16,2 +16,2 @@
-fn greet(gpa: Gpa) -> Buf<Gpa> {
-    var b = Buf::new_in(gpa);
+fn greet(gpa: Gpa) -> String<Gpa> {
+    var b = String::new_in(gpa);
@@ -23 +23 @@
-fn put(out: inout Buf<Gpa>, x: u8) {
+fn put(out: inout Vec<u8, Gpa>, x: u8) {
@@ -28 +28 @@
-fn first_word(gpa: Gpa, s: [u8]) -> Option<Buf<Gpa>> {
+fn first_word(gpa: Gpa, s: [u8]) -> Option<Vec<u8, Gpa>> {
@@ -32,2 +32,2 @@
-    var w = Buf::new_in(gpa);
-    w.push_str(s[0..1]);
+    var w = Vec::<u8, Gpa>::new_in(gpa);
+    w.extend_from_slice(s[0..1]);
@@ -49 +49 @@
-    var t = Buf::new_in(gpa);
+    var t = String::new_in(gpa);
@@ -52,2 +52,2 @@
-    var fb = Buf::new_in(gpa);
-    fb.push_fmt("{}", 7);
+    var fb = Vec::<u8, Gpa>::new_in(gpa);
+    fb.extend_from_slice(format_in("{}", 7, fb.allocator()).as_bytes());
@@ -56 +56 @@
-    var a = Buf::new_in(gpa);
+    var a = String::new_in(gpa);
@@ -60 +60 @@
-    var hi = Buf::new_in(gpa);
+    var hi = Vec::<u8, Gpa>::new_in(gpa);
@@ -64,2 +64,2 @@
-    var r = Buf::new_in(gpa);
-    r.push_str(raw);
+    var r = Vec::<u8, Gpa>::new_in(gpa);
+    r.extend_from_slice(raw);
@@ -68 +68 @@
-    var log = Log { lines: Buf::new_in(gpa), count: 0 };
+    var log = Log { lines: String::new_in(gpa), count: 0 };
@@ -72,2 +72,2 @@
-    var p = Buf::new_in(gpa);
-    p.push_str("dir");
+    var p = Vec::<u8, Gpa>::new_in(gpa);
+    p.extend_from_slice("dir");
@@ -75 +75 @@
-    p.push_str(HEAD);
+    p.extend_from_slice(HEAD);
@@ -78 +78 @@
-    var mt = Buf::new_in(gpa);
+    var mt = String::new_in(gpa);
@@ -82 +82 @@
-    var cap = Buf::new_in(gpa);
+    var cap = Vec::<u8, Gpa>::new_in(gpa);
@@ -98 +98 @@
-    var e = Buf::new_in(gpa);
+    var e = Vec::<u8, Gpa>::new_in(gpa);
note fix.buf-refused: 'b' at main.vl:39:9: a by-value parameter, written at main.vl:40:5 (a Buf there is the caller's, a String or a Vec a copy): make it `inout` first (refactor signature)
note fix.buf-refused: 'm' at main.vl:86:9: mixed: text (printed as text at main.vl:122:16) and bytes (push of a byte that is not a constant at main.vl:89:5)
note fix.buf-refused: 'f' at main.vl:91:9: passed to std's 'String<Gpa>::from_buf' at main.vl:93:31, which takes a Buf
note fix.buf-refused: 'c' at main.vl:95:9: text, but its 'take' at main.vl:96:17 has no String<A> form
note fix.buf-table: Buf's methods, as String<A> (text) and Vec<u8, A> (bytes); '-': none, the binding is refused
  new_in -> String::new_in | Vec::<u8>::new_in
  with_capacity_in -> String::with_capacity_in | Vec::<u8>::with_capacity_in
  from_in -> String::from_in | -
  len -> len | len
  push -> push | push
  push_str -> push_str | extend_from_slice
  push_fmt -> push_fmt | extend_from_slice(format_in(.., v.allocator()).as_bytes())
  push_int -> push_fmt | extend_from_slice(format_in("{}", .., v.allocator()).as_bytes())
  push_cstr -> - | -
  as_slice -> as_slice | as_slice
  as_mut_slice -> - | as_mut_slice
  clear -> clear | clear
  free -> free | free
  take -> - | take
  capacity -> capacity | capacity
  reserve -> reserve | reserve
  allocator -> allocator | allocator
  clone -> clone | clone
[exit 1]
$ fix --only buf
fixed 22 Buf sites	main.vl	+22 -22 lines
note fix.buf-refused: 'b' at main.vl:39:9: a by-value parameter, written at main.vl:40:5 (a Buf there is the caller's, a String or a Vec a copy): make it `inout` first (refactor signature)
note fix.buf-refused: 'm' at main.vl:86:9: mixed: text (printed as text at main.vl:122:16) and bytes (push of a byte that is not a constant at main.vl:89:5)
note fix.buf-refused: 'f' at main.vl:91:9: passed to std's 'String<Gpa>::from_buf' at main.vl:93:31, which takes a Buf
note fix.buf-refused: 'c' at main.vl:95:9: text, but its 'take' at main.vl:96:17 has no String<A> form
note fix.buf-table: Buf's methods, as String<A> (text) and Vec<u8, A> (bytes); '-': none, the binding is refused
  new_in -> String::new_in | Vec::<u8>::new_in
  with_capacity_in -> String::with_capacity_in | Vec::<u8>::with_capacity_in
  from_in -> String::from_in | -
  len -> len | len
  push -> push | push
  push_str -> push_str | extend_from_slice
  push_fmt -> push_fmt | extend_from_slice(format_in(.., v.allocator()).as_bytes())
  push_int -> push_fmt | extend_from_slice(format_in("{}", .., v.allocator()).as_bytes())
  push_cstr -> - | -
  as_slice -> as_slice | as_slice
  as_mut_slice -> - | as_mut_slice
  clear -> clear | clear
  free -> free | free
  take -> - | take
  capacity -> capacity | capacity
  reserve -> reserve | reserve
  allocator -> allocator | allocator
  clone -> clone | clone
[exit 1]
$ check
main.vl:39:12: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:86:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:91:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:95:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:99:14: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
ok: 0 errors, 5 warnings in main.vl
% volec main.vl -o after >/dev/null && ./after 2>&1
hello
1 + 2 = 3
7!
ok
1
4
started
Dir/head;
42
v
5
from_buf
taken
2
[a	]
main.vl:39:12: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:86:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:91:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:95:13: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:99:14: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
ok: built after
$ explain fix.buf-refused
fix.buf-refused: note, exit 1
(0.26.3) `fix --only buf` left a std `Buf` binding as it is: a local, a parameter, a field or a result, with the bindings its value flows between (through an Option or a Vec that holds it, a pattern, an enum variant's field, a closure's capture too). It writes `Vec<u8, A>` when a write says bytes (a non-constant byte, a constant at or above 0x80, a push_str of a [u8], an index) or none does, and `String<A>` when a write says text and none bytes (a push_str of a str and a constant byte below 0x80 are the same bytes in a Vec, and a format write is `extend_from_slice(format_in(.., v.allocator()).as_bytes())` there, so they give way to bytes). Refused: a Buf printed or given to a String, with bytes (mixed), a binding passed to a std function whose parameter is written Buf, one written through a by-value parameter, and a method that has no form on the side decided (fix.buf-table).
fix: Write the type by hand: `String<A>` for text, `Vec<u8, A>` for bytes (a push of 0xC3 is one byte in a Vec, two in a String, which pushes a code point). The note names the writes on each side.
example:
    note fix.buf-refused: 'm' at main.vl:41:9: mixed: text (printed as text at main.vl:42:5) and bytes (push of a byte that is not a constant at main.vl:44:5)
$ explain fix.buf-table
fix.buf-table: note
(0.26.3) The table `fix --only buf` maps Buf's methods through: each method, its String<A> form and its Vec<u8, A> form (`push_str` is `extend_from_slice` on a Vec; `-`: none, and a binding that calls it on that side is refused).
fix: Nothing to do: it is printed with every run, so a reader knows what each call became.
example:
    note fix.buf-table: Buf's methods, as String<A> (text) and Vec<u8, A> (bytes); '-': none, the binding is refused
