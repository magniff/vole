## 0.26.3: allocation as a capability (tests/refactor/alloc0263/). alloc.default:
## a container written without its allocator; `fix --only alloc` writes Gpa,
## what the 0.26.2 default meant, but not in an item generic over an
## allocator (`grow`'s `w`, left with its reason); a declared default is taken
## out. alloc.no_in: a constructor without `_in` (`Vec::new()`, `collect()`);
## the fix passes the allocator in scope, and leaves `empty`, which has none.
## alloc.field: `Bag` holds a Gpa; the fix makes it `Bag<A: Allocator>`, and
## its use `Bag<Gpa>` (the next round). `Stack<T>`'s field, then its impl's
## header (alloc.default: `impl<T, A: Allocator> Stack<T, A>`), then its own
## `Stack<T>` inside it, written with the impl's `A`; a turbofish, `Vec::<i64>`.
## Then the codes' explanations (alloc.safe_impl, alloc.static, alloc.field, alloc.last: their tests/run/err_alloc_* cases).
$ check
main.vl:7:25: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:3:13: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:7:12: error[alloc.default] 'HashMap' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:7:25: error[alloc.default] 'Buf' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
main.vl:15:13: error[alloc.default] the allocator parameter 'A' has a default: an allocator type is always written (0.26.3) | help: take the default out: each use writes its allocator (`Vec<u8, Gpa>`) | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:20:5: error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'empty' and pass it down | try: volec fix --only alloc main.vl
main.vl:24:28: error[alloc.no_in] 'collect' allocates from nothing: pass the allocator, last, to 'collect_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:32:12: error[alloc.field] the struct 'Bag' holds an allocator its parameters do not name: 'Gpa', in field 'items' | help: a type that holds an allocator says so in its parameters: make it generic over it (`struct P<A: Allocator> { v: Vec<u8, A> }`, used as `P<Gpa>`) | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:55:13: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: the allocator is part of the type: `Gpa` (main's, what the default meant), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
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
@@ -31,2 +31,2 @@
-struct Bag {
-    items: Vec<i64, Gpa>,
+struct Bag<A: Allocator> {
+    items: Vec<i64, A>,
@@ -35 +35 @@
-fn bag_len(b: Bag) -> usize {
+fn bag_len(b: Bag<Gpa>) -> usize {
@@ -39,2 +39,2 @@
-struct Stack<T> {
-    items: Vec<T>,
+struct Stack<T, A: Allocator> {
+    items: Vec<T, A>,
@@ -43 +43 @@
-impl<T> Stack<T> {
+impl<T, A: Allocator> Stack<T, A> {
@@ -49 +49 @@
-    fn me(sink self) -> Stack<T> {
+    fn me(sink self) -> Stack<T, A> {
@@ -55 +55 @@
-    let u = Vec::<i64>::new_in(gpa);
+    let u = Vec::<i64, Gpa>::new_in(gpa);
$ fix --only alloc
fixed 12 suggested fixes	main.vl	+12 -12 lines
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
main.vl:20:5: error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'empty' and pass it down | try: volec fix --only alloc main.vl
note fix.left: 2 errors left (above)
$ check
main.vl:7:25: warning[item.deprecated] use of deprecated struct 'Buf': use String<A> for text, Vec<u8, A> for bytes (volec fix --only buf) | help: marked #[deprecated] at <std>:518:5
main.vl:11:48: error[alloc.default] 'Vec' names no allocator: its 'A' is written (no default allocator type since 0.26.3) | help: this item is generic over the allocator 'A': write it, or Gpa (what the default meant) | try: volec fix --only alloc main.vl
main.vl:20:5: error[alloc.no_in] 'Vec::new' allocates from nothing: pass the allocator, last, to 'Vec::new_in' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'empty' and pass it down | try: volec fix --only alloc main.vl
[exit 1]
$ explain alloc.default
alloc.default: error
(0.26.3) A container of std written without its allocator type, `Vec<u8>`, `Buf`, `HashMap<K, V>`: std's types have no default allocator (until 0.26.3 the default was Gpa), so the allocator a value may grow from is in its type, and a signature says what a function may allocate from. Also a type parameter bounded by Allocator declared with a default (`A: Allocator = Gpa`).
fix: Write the allocator: `Vec<u8, Gpa>` (main's, what the default meant), or the allocator parameter of a generic item (`fn fill<A: Allocator>(v: &mut Vec<u8, A>)`); a function that only reads takes a slice, `[u8]`. `volec fix --only alloc` writes Gpa, except in an item generic over an allocator, where it is yours to choose (in its own generic impl, the program's type gets the impl's `A`; an impl block without the allocator gets the parameter).
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
$ explain alloc.safe_impl
alloc.safe_impl: error
(0.26.3) An impl of std's Allocator written `impl Allocator for T`: Allocator is an `unsafe trait`, as in Rust. Containers' unsafe code relies on an allocator's blocks, and a type made from nothing over malloc is a global allocator, so its impl says so. (Any `unsafe trait`'s impl is `unsafe impl`; `unsafe impl` of a safe trait, or of a type alone, is an error.)
fix: Write `unsafe impl Allocator for T`, under `// UNSAFE:` (why it cannot be safe) and `// SAFETY:` (where its memory comes from, why its blocks are sound). No tool writes it: the comments are the author's.
example:
    impl Allocator for Heap { .. }
    
    main.vl:1:1: error[alloc.safe_impl] the trait 'Allocator' is unsafe: its impl is `unsafe impl` | help: an allocator says where its memory comes from: `unsafe impl Allocator for T`, under `// UNSAFE:` (why it cannot be safe) and `// SAFETY:` (where its memory comes from, why it is sound)
$ explain alloc.static
alloc.static: error
(0.26.3) A `static`, `static var` or thread-local whose type holds an allocator (`Option<Vec<u8, Gpa>>`, an Arena, a struct holding one, through a pointer too): any function could allocate through it with nothing in its signature saying so. So a static's type is AllocFree (the auto trait, `T: AllocFree`), and an allocator value inside a function came in through a parameter.
fix: Keep the container in main, or in the struct the program's work is done on, and pass it (or what it allocated, as a slice) down. A static may hold what holds no allocator: integers, arrays, atomics, text. No tool moves it.
example:
    static var NAMES: Option<Vec<i64, Gpa>> = None;
    
    main.vl:1:1: error[alloc.static] the static 'NAMES' holds an allocator, 'Gpa' (in its type 'Option<Vec<i64, Gpa>>'): a static's type may not hold one
$ explain alloc.field
alloc.field: error
(0.26.3) A struct's field or an enum variant's payload holds an allocator that the type's parameters do not name (`struct Parser { toks: Vec<Tok, Gpa> }`): `fn f(p: inout Parser)` could allocate with nothing in its signature saying so. A type that holds an allocator says so in its parameters.
fix: Make the type generic over the allocator, `struct Parser<A: Allocator> { toks: Vec<Tok, A> }`, and name it at each use, `Parser<Gpa>`: `volec fix --only alloc` does both, in rounds (the parameter, then the uses). A literal infers it from its fields (`Parser { toks: Vec::new_in(gpa) }`).
example:
    struct Parser { toks: Vec<i64, Gpa> }
    
    main.vl:1:23: error[alloc.field] the struct 'Parser' holds an allocator its parameters do not name: 'Gpa', in field 'toks'
$ explain alloc.last
alloc.last: error
(0.26.3) A function named `..._in` whose allocator parameter is not its last: an `_in` function takes its allocator last, as Rust's allocator API does (`Vec::with_capacity_in(cap, alloc)`), so that every allocating call reads the same way.
fix: Move the allocator to the end of the parameters and of every call: `volec refactor signature` does both.
example:
    fn copy_in<A: Allocator>(a: A, s: [u8]) -> Vec<u8, A>
    
    main.vl:1:26: error[alloc.last] 'copy_in' takes its allocator 'a' before its last parameter: an `_in` function takes it last
