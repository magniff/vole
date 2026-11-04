## 0.26.3: allocation as a capability (tests/refactor/alloc0263/). alloc.default:
## a container written without its allocator; `fix --only alloc` writes Gpa,
## what the 0.26.2 default meant, but not in an item generic over an
## allocator (`grow`'s `w`, left with its reason); a declared default is taken
## out. alloc.no_in: a constructor without `_in` (`Vec::new()`, `collect()`);
## the fix passes the allocator in scope, and leaves `empty`, which has none.
## Then the codes' explanations.
$ check
main.vl:3:13: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:7:12: error[alloc.default] 'HashMap' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:7:25: error[alloc.default] 'Buf' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
main.vl:15:13: error[alloc.default] the allocator parameter 'A' has a default: an allocator type is always written (0.26.3) | help: take the default out: each use writes its allocator (`Vec<u8, Gpa>`) | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:20:5: error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'empty' and pass it down | try: volec fix --only alloc main.vl
main.vl:24:28: error[alloc.no_in] 'collect' allocates from nothing: pass the allocator, last, to 'collect_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
[exit 1]
$ fix --only alloc --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-fn total(v: Vec<i64>) -> i64 {
+fn total(v: Vec<i64, Gpa>) -> i64 {
@@ -7 +7 @@
-fn keys(m: HashMap<i64, Buf>) -> usize {
+fn keys(m: HashMap<i64, Buf<Gpa>, Gpa>) -> usize {
@@ -15 +15 @@
-struct Pool<A: Allocator = Gpa> {
+struct Pool<A: Allocator> {
@@ -24 +24 @@
-    let t: Vec<i64, Gpa> = (0..3).collect();
+    let t: Vec<i64, Gpa> = (0..3).collect_in(gpa);
$ fix --only alloc
fixed 5 suggested fixes	main.vl	+4 -4 lines
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
main.vl:20:5: error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'empty' and pass it down | try: volec fix --only alloc main.vl
note fix.left: 2 errors left (above)
$ check
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
main.vl:20:5: error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'empty' and pass it down | try: volec fix --only alloc main.vl
[exit 1]
$ explain alloc.default
alloc.default: error
(0.26.3) A container of std written without its allocator type, `Vec<u8>`, `Buf`, `HashMap<K, V>`: std's types have no default allocator (until 0.26.3 the default was Gpa), so the allocator a value may grow from is in its type, and a signature says what a function may allocate from. Also a type parameter bounded by Allocator declared with a default (`A: Allocator = Gpa`).
fix: Write the allocator: `Vec<u8, Gpa>` (main's, what the default meant), or the allocator parameter of a generic item (`fn fill<A: Allocator>(v: &mut Vec<u8, A>)`); a function that only reads takes a slice, `[u8]`. `volec fix --only alloc` writes Gpa, except in an item generic over an allocator, where it is yours to choose.
example:
    fn total(v: Vec<i64>) -> i64 { v.iter().sum() }
    
    main.vl:1:13: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator`
$ explain alloc.no_in
alloc.no_in: error
(0.26.3) A constructor or function that allocated from an allocator nobody passed (`Vec::new()`, `with_capacity(n)`, `collect()`, `format(x)`, `s.to_string()`): std has none of them. Every allocation names its allocator, as the last argument of the `_in` form (`Vec::new_in(a)`, `collect_in(a)`, `format_in(x, a)`).
fix: Call the `_in` form with the allocator: a parameter (`gpa: Gpa`, from main's `fn main(gpa: Gpa)`), or a container's (`v.alloc()`). `volec fix --only alloc` writes it when one allocator value is in scope, and says so when none or several are.
example:
    let v: Vec<i64, Gpa> = Vec::new();
    
    main.vl:2:28: error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in' | help: this function's `gpa` is the allocator to pass
