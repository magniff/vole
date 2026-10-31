## 0.26.3: allocation as a capability (tests/refactor/alloc0263/). alloc.default:
## a container written without its allocator; `fix --only alloc` writes Gpa,
## what the 0.26.2 default meant, but not in an item generic over an
## allocator (`grow`'s `w`, left with its reason); a declared default is taken
## out. Then the codes' explanations.
$ check
main.vl:3:13: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:7:12: error[alloc.default] 'HashMap' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:7:25: error[alloc.default] 'Buf' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
main.vl:15:13: error[alloc.default] the allocator parameter 'A' has a default: an allocator type is always written (0.26.3) | help: take the default out: each use writes its allocator (`Vec<u8, Gpa>`) | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
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
$ fix --only alloc
fixed 4 suggested fixes	main.vl	+3 -3 lines
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
note fix.left: 1 error left (above)
$ check
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
[exit 1]
$ explain alloc.default
alloc.default: error
(0.26.3) A container of std written without its allocator type, `Vec<u8>`, `Buf`, `HashMap<K, V>`: std's types have no default allocator (until 0.26.3 the default was Gpa), so the allocator a value may grow from is in its type, and a signature says what a function may allocate from. Also a type parameter bounded by Allocator declared with a default (`A: Allocator = Gpa`).
fix: Write the allocator: `Vec<u8, Gpa>` (main's, what the default meant), or the allocator parameter of a generic item (`fn fill<A: Allocator>(v: &mut Vec<u8, A>)`); a function that only reads takes a slice, `[u8]`. `volec fix --only alloc` writes Gpa, except in an item generic over an allocator, where it is yours to choose.
example:
    fn total(v: Vec<i64>) -> i64 { v.iter().sum() }
    
    main.vl:1:13: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator`
