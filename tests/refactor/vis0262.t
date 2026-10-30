## 0.26.2: restricted visibility (tests/refactor/vis0262/): a use outside
## `pub(super)` or `pub(in path)` is item.private or field.private, which
## say where the item is visible; `fix --only pub` widens the restriction
## to `pub(crate)` (a program is one crate) and makes `pub(self)` `pub`;
## query context shows a field's restriction.
$ check
main.vl:15:13: error[item.private] 'super_fn' is visible only in module 'outer' | help: make it visible in its crate: `pub(crate) fn super_fn` at main.vl:3:20 | try: volec fix --suggested main.vl
main.vl:16:13: error[item.private] 'self_fn' is private | help: make it public: `pub fn self_fn` at main.vl:4:19 | try: volec fix --suggested main.vl
main.vl:17:13: error[item.private] 'in_fn' is visible only in module 'outer::a' | help: make it visible in its crate: `pub(crate) fn in_fn` at main.vl:5:33 | try: volec fix --suggested main.vl
main.vl:18:13: error[field.private] field 's' of 'S' is visible only in module 'outer' | help: make it visible in its crate: 'pub(crate) s: i64' at main.vl:6:24 | try: volec fix --suggested main.vl
[exit 1]
$ query context outer::a::S.s
// crate::outer::a::S.s	main.vl:6-6	pub(super) field
        pub struct S { pub(super) s: i64, pub c: i64 }
// used by (2)
outer::a::make	main.vl:9:17	S { s: 2, c: 1 }
main	main.vl:18:30	let d = outer::a::make().s;
warning query.program-errors: 4 errors in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
$ fix --only pub --dry-run
--- a/main.vl
+++ b/main.vl
@@ -3,4 +3,4 @@
-        pub(super) fn super_fn() -> i64 { 2 }
-        pub(self) fn self_fn() -> i64 { 3 }
-        pub(in crate::outer::a) fn in_fn() -> i64 { 4 }
-        pub struct S { pub(super) s: i64, pub c: i64 }
+        pub(crate) fn super_fn() -> i64 { 2 }
+        pub fn self_fn() -> i64 { 3 }
+        pub(crate) fn in_fn() -> i64 { 4 }
+        pub struct S { pub(crate) s: i64, pub c: i64 }
$ fix --only pub
fixed 4 pubs	main.vl	+4 -4 lines
$ check
ok: 0 errors in main.vl
$ explain item.private
item.private: error
(0.26.2) An item (a function, a type, a constant, a static, a module) used outside the module that declares it, where it is not visible (Rust's E0603): an item not marked `pub` is private to its module and the modules inside it; one marked `pub(crate)`, `pub(super)` or `pub(in path)` is visible only up to that module (the message says which: `crate 'std'`, `module 'a::b'`). Until 0.26.2 this was a `type error`.
fix: In your own program, mark it `pub` where it is declared, or widen its restriction (the help gives the declaration; `volec fix --only pub` writes `pub` for a private one and `pub(crate)` for a restricted one). Std's `pub(crate)` items are std's own: use its public API.
example:
    error[item.private] 'super_fn' is visible only in module 'outer' | help: make it visible in its crate: `pub(crate) fn super_fn` at main.vl:3:20
$ explain vis.path
vis.path: error
(0.26.2) `pub(in path)` whose path names no module, or a module that is not the item's own or one around it (Rust's E0742); or `pub(super)` at a crate's root, which has no parent in the crate. The path starts at `crate`, `self`, `super` (in std, `std::` or `super::`). The item is then visible in its crate.
fix: Name the item's module or one of its ancestors: `pub(in crate::a)` for an item of `a::b`, or write `pub(super)` or `pub(crate)`.
example:
    error[vis.path] 'pub(in crate::outer::b)': the path names a module that is not around this item | help: 'pub(in path)' names the item's module or one around it: 'pub(in crate::a)', 'pub(super)', 'pub(crate)'
