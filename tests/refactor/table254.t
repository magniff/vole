## 0.25.4: `volec refactor table X` (tests/refactor/table254/): a table
## kept as a raw pointer, a count and a capacity becomes a Vec<T, Comp>;
## every use is placed, or the refactor is refused and changes nothing.
## (0.26.5) A static may not hold Comp any more (the alloc exemption names
## two of the compiler's own statics only, base::SYMS and
## front::types::TYPES): each rewrite's dry run shows its diff, and the
## rewrite is refused (alloc.static) and changes nothing. A table in a
## context's field is the next form the refactor takes.
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
4 10 36 40
2 8 23
100 297 411
5 100
3 7
## Each rewrite: the grow goes, the store and its increment are a push
## (reads between them one less), reads are len(), `= 0` clear, `-= k`
## truncate; the count's and the capacity's statics and imports go, the
## table's import comes where a file read only the count (count.vl), a
## path keeps its prefix (report.vl).
$ refactor table ITEMS --dry-run
--- a/main.vl
+++ b/main.vl
@@ -11 +11 @@
-use crate::items::{ITEM_COUNT, add_item, add_pair, drop_last, drop_some, reset_items, total};
+use crate::items::{ITEMS, add_item, add_pair, drop_last, drop_some, reset_items, total};
@@ -30 +30,2 @@
-    println("{} {} {} {}", ITEM_COUNT, total(), crate::items::PLACES, crate::count::count());
+    println("{} {} {} {}", ITEMS.len() as i64, total(), crate::items::PLACES,
+        crate::count::count());
--- a/count.vl
+++ b/count.vl
@@ -2 +1,0 @@
-use crate::items::ITEM_COUNT;
@@ -3,0 +3,2 @@
+use crate::items::ITEMS;
+
@@ -5 +6 @@
-    ITEM_COUNT * 10
+    ITEMS.len() as i64 * 10
--- a/items.vl
+++ b/items.vl
@@ -2 +1,0 @@
-use crate::base::grow;
@@ -3,0 +3,2 @@
+use crate::base::comp::Comp;
+
@@ -9,3 +10 @@
-pub static var ITEMS: *Item = 0 as *Item;
-pub static var ITEM_COUNT: i64 = 0;
-static var ITEM_CAP: i64 = 0;
+pub static var ITEMS: Vec<Item, Comp> = Vec::new_in(Comp {});
@@ -18,3 +17,2 @@
-        ITEMS = grow(ITEMS, ITEM_COUNT, &ITEM_CAP);
-        ITEMS[ITEM_COUNT] = Item { v, next: ITEM_COUNT + 1 };
-        PLACES += ITEM_COUNT * 2 + (ITEM_COUNT + 1);
+        ITEMS.push(Item { v, next: ITEMS.len() as i64 + 1 });
+        PLACES += (ITEMS.len() as i64 - 1) * 2 + ITEMS.len() as i64;
@@ -22,2 +20 @@
-    ITEM_COUNT += 1;
-    ITEM_COUNT - 1
+    ITEMS.len() as i64 - 1
@@ -29,4 +26,2 @@
-        ITEMS = grow(ITEMS, ITEM_COUNT, &ITEM_CAP);
-        let n = ITEM_COUNT;
-        ITEMS[n] = Item { v, next: -1 };
-        ITEM_COUNT += 1;
+        let n = ITEMS.len() as i64;
+        ITEMS.push(Item { v, next: -1 });
@@ -38 +33 @@
-    ITEM_COUNT = 0;
+    ITEMS.clear();
@@ -42 +37 @@
-    ITEM_COUNT -= k;
+    ITEMS.truncate(ITEMS.len() - k as usize);
@@ -46 +41 @@
-    ITEM_COUNT -= k - 1;
+    ITEMS.truncate(ITEMS.len() - (k - 1) as usize);
@@ -51 +46 @@
-    for i in 0..ITEM_COUNT {
+    for i in 0..ITEMS.len() as i64 {
--- a/report.vl
+++ b/report.vl
@@ -2 +2 @@
-use crate::items::{ITEMS, ITEM_COUNT};
+use crate::items::ITEMS;
@@ -6 +6 @@
-    for i in 0..ITEM_COUNT {
+    for i in 0..ITEMS.len() as i64 {
@@ -9 +9 @@
-    s + crate::items::ITEM_COUNT * 100 + unsafe { crate::items::ITEMS[0].v }
+    s + crate::items::ITEMS.len() as i64 * 100 + unsafe { crate::items::ITEMS[0].v }
items.vl:10:5: error[alloc.static] the static 'ITEMS' holds an allocator, 'Comp' (in its type 'Vec<Item, Comp>'): a static's type may not hold one | help: any function could allocate through it with nothing in its signature saying so: keep the value in main and pass it down (or what it allocates, as a slice)  [edited: crate::items::ITEMS]
note edit.imports: added the imports the new text needs (fix --only imports)
warning edit.breaks: 1 new error (dry run); the error: items.vl:10:5: the static 'ITEMS' holds an allocator, 'Comp' (in its type 'Vec<Item, Comp>'): a static's type may not hold one
[exit 1]
## The increment before the store (at a local set before it): reads
## between them one more.
$ refactor table MARKS --dry-run
--- a/main.vl
+++ b/main.vl
@@ -31 +31 @@
-    println("{} {} {}", crate::marks::MARK_COUNT, last(), crate::marks::seen(1));
+    println("{} {} {}", crate::marks::MARKS.len() as i64, last(), crate::marks::seen(1));
--- a/marks.vl
+++ b/marks.vl
@@ -2 +1,0 @@
-use crate::base::grow;
@@ -3,0 +3,2 @@
+use crate::base::comp::Comp;
+
@@ -9,3 +10 @@
-pub static var MARKS: *Mark = 0 as *Mark;
-pub static var MARK_COUNT: i64 = 0;
-pub static var MARK_CAP: i64 = 0;
+pub static var MARKS: Vec<Mark, Comp> = Vec::new_in(Comp {});
@@ -15,5 +14,3 @@
-        let id = MARK_COUNT;
-        MARKS = grow(MARKS, MARK_COUNT, &MARK_CAP);
-        MARK_COUNT += 1;
-        let seen = MARK_COUNT - 1 + MARK_COUNT * 10;
-        MARKS[id] = Mark { at, seen: seen + MARK_COUNT };
+        let id = MARKS.len() as i64;
+        let seen = MARKS.len() as i64 + (MARKS.len() as i64 + 1) * 10;
+        MARKS.push(Mark { at, seen: seen + (MARKS.len() as i64 + 1) });
@@ -25 +22 @@
-    unsafe { MARKS[MARK_COUNT - 1].at }
+    unsafe { MARKS[MARKS.len() as i64 - 1].at }
marks.vl:10:5: error[alloc.static] the static 'MARKS' holds an allocator, 'Comp' (in its type 'Vec<Mark, Comp>'): a static's type may not hold one | help: any function could allocate through it with nothing in its signature saying so: keep the value in main and pass it down (or what it allocates, as a slice)  [edited: crate::marks::MARKS]
note edit.imports: added the imports the new text needs (fix --only imports)
warning edit.breaks: 1 new error (dry run); the error: marks.vl:10:5: the static 'MARKS' holds an allocator, 'Comp' (in its type 'Vec<Mark, Comp>'): a static's type may not hold one
[exit 1]
## A grow in `if TOK_COUNT >= TOK_CAP { ... }`: the `if` goes with it;
## `TOKS = reserve(TOKS, &TOK_CAP, n)` (room for n in all) is a Vec's
## reserve of what is missing.
## (0.25.5) `TOK_COUNT = mark`, mark a `let` set to the count before and
## assigned nowhere (a rollback), is `TOKS.truncate(mark)`.
$ refactor table TOKS --dry-run
--- a/main.vl
+++ b/main.vl
@@ -13 +13 @@
-use crate::tokens::{TOK_COUNT, add_tok, reserve_toks};
+use crate::tokens::{TOKS, add_tok, reserve_toks};
@@ -32,2 +32,2 @@
-    println("{} {} {}", TOK_COUNT, crate::tokens::tok(99), crate::report::report());
-    println("{} {}", crate::tokens::try_toks(5), TOK_COUNT);
+    println("{} {} {}", TOKS.len() as i64, crate::tokens::tok(99), crate::report::report());
+    println("{} {}", crate::tokens::try_toks(5), TOKS.len() as i64);
--- a/tokens.vl
+++ b/tokens.vl
@@ -2 +1,0 @@
-use crate::base::{grow, reserve};
@@ -4,3 +3 @@
-pub static var TOKS: *i64 = 0 as *i64;
-pub static var TOK_COUNT: i64 = 0;
-static var TOK_CAP: i64 = 0;
+use crate::base::comp::Comp;
@@ -7,0 +5,2 @@
+pub static var TOKS: Vec<i64, Comp> = Vec::new_in(Comp {});
+
@@ -10 +9 @@
-    TOKS = reserve(TOKS, &TOK_CAP, n + 1);
+    TOKS.reserve((n + 1 - TOKS.len() as i64).max(0) as usize);
@@ -15,4 +14 @@
-        if TOK_COUNT >= TOK_CAP {
-            TOKS = grow(TOKS, TOK_COUNT, &TOK_CAP);
-        }
-        TOKS[TOK_COUNT] = t * 3;
+        TOKS.push(t * 3);
@@ -20 +15,0 @@
-    TOK_COUNT += 1;
@@ -30 +25 @@
-    let mark = TOK_COUNT;
+    let mark = TOKS.len() as i64;
@@ -34,2 +29,2 @@
-    let added = TOK_COUNT - mark;
-    TOK_COUNT = mark;
+    let added = TOKS.len() as i64 - mark;
+    TOKS.truncate(mark as usize);
tokens.vl:5:5: error[alloc.static] the static 'TOKS' holds an allocator, 'Comp' (in its type 'Vec<i64, Comp>'): a static's type may not hold one | help: any function could allocate through it with nothing in its signature saying so: keep the value in main and pass it down (or what it allocates, as a slice)  [edited]
note edit.imports: added the imports the new text needs (fix --only imports)
warning edit.breaks: 1 new error (dry run); the error: tokens.vl:5:5: the static 'TOKS' holds an allocator, 'Comp' (in its type 'Vec<i64, Comp>'): a static's type may not hold one
[exit 1]
## Refused, each use listed: a pointer into the table, the table passed
## and assigned, the capacity read, the count written, a call between the
## store and its increment that reads the count, (0.25.5) a call in an
## index that may grow the table (its header is read before the call).
$ refactor table BADS
error refactor.table-use: crate::refused::BADS: 7 uses refactor table cannot place; nothing changed
refused.vl:24:9: `noted()`: a call between the store and `BAD_COUNT += 1` reaches code naming BAD_COUNT (it would see the count changed): move the `+= 1` next to the store first
refused.vl:27:19: `&BADS[0]`: a pointer into the table (`&BADS[i]`): kept past a push it dangles; take the index, or the element by value
refused.vl:31:5: `BAD_COUNT = n`: BAD_COUNT written (a Vec's length changes by push, clear and truncate only)
refused.vl:35:5: `BAD_CAP - BAD_COUNT`: BAD_CAP read outside the grow (a Vec's capacity is its own)
refused.vl:40:14: `BADS as *u8`: the table itself used (passed, assigned, compared, freed): a Vec is not its pointer
refused.vl:42:5: `BADS = 0 as *Bad`: the table itself used (passed, assigned, compared, freed): a Vec is not its pointer
refused.vl:69:19: `again()`: a call in BADS[i]'s index that may grow BADS (BADS's buffer and length are read before it): take the index into a `let` first
note refactor.table-why: 1: a call between the store and `BAD_COUNT += 1` reaches code naming BAD_COUNT (it would see the count changed): move the `+= 1` next to the store first
note refactor.table-why: 1: a pointer into the table (`&BADS[i]`): kept past a push it dangles; take the index, or the element by value
note refactor.table-why: 2: the table itself used (passed, assigned, compared, freed): a Vec is not its pointer
note refactor.table-why: 1: a call in BADS[i]'s index that may grow BADS (BADS's buffer and length are read before it): take the index into a `let` first
note refactor.table-why: 1: BAD_COUNT written (a Vec's length changes by push, clear and truncate only)
note refactor.table-why: 1: BAD_CAP read outside the grow (a Vec's capacity is its own)
help: change these by hand (or with rewrite), then run refactor table again
try: volec query refs crate::refused::BADS
[exit 1]
## A return between the store and the increment.
$ refactor table RETS
error refactor.table-use: crate::refused::RETS: 1 use refactor table cannot place; nothing changed
refused.vl:55:13: `return`: a return, ? or break between the store and `RET_COUNT += 1` (the push and the count would part)
help: change these by hand (or with rewrite), then run refactor table again
try: volec query refs crate::refused::RETS
[exit 1]
## Not a table; no count static by that name; no such static.
$ refactor table PLACES
error refactor.table-shape: crate::items::PLACES is not a `static var X: *T` of the program (a table's pointer)
try: volec query show crate::items::PLACES
[exit 1]
$ refactor table ITEMS --count NOPE
error refactor.table-count: crate::items::ITEMS has no count static (NOPE not found in its module)
try: volec refactor table crate::items::ITEMS --count NAME --dry-run
[exit 1]
$ refactor table Item
error refactor.kind: crate::items::Item is a struct, not a static
try: volec query def Item
[exit 1]
## The rewrites, written: the program prints what it printed.
$ refactor table ITEMS
items.vl:10:5: error[alloc.static] the static 'ITEMS' holds an allocator, 'Comp' (in its type 'Vec<Item, Comp>'): a static's type may not hold one | help: any function could allocate through it with nothing in its signature saying so: keep the value in main and pass it down (or what it allocates, as a slice)  [edited: crate::items::ITEMS]
note edit.imports: added the imports the new text needs (fix --only imports)
error edit.breaks: 1 new error; nothing written; the error: items.vl:10:5: the static 'ITEMS' holds an allocator, 'Comp' (in its type 'Vec<Item, Comp>'): a static's type may not hold one
try: volec refactor table ITEMS --no-check
[exit 1]
$ refactor table MARKS
marks.vl:10:5: error[alloc.static] the static 'MARKS' holds an allocator, 'Comp' (in its type 'Vec<Mark, Comp>'): a static's type may not hold one | help: any function could allocate through it with nothing in its signature saying so: keep the value in main and pass it down (or what it allocates, as a slice)  [edited: crate::marks::MARKS]
note edit.imports: added the imports the new text needs (fix --only imports)
error edit.breaks: 1 new error; nothing written; the error: marks.vl:10:5: the static 'MARKS' holds an allocator, 'Comp' (in its type 'Vec<Mark, Comp>'): a static's type may not hold one
try: volec refactor table MARKS --no-check
[exit 1]
$ refactor table TOKS
tokens.vl:5:5: error[alloc.static] the static 'TOKS' holds an allocator, 'Comp' (in its type 'Vec<i64, Comp>'): a static's type may not hold one | help: any function could allocate through it with nothing in its signature saying so: keep the value in main and pass it down (or what it allocates, as a slice)  [edited]
note edit.imports: added the imports the new text needs (fix --only imports)
error edit.breaks: 1 new error; nothing written; the error: tokens.vl:5:5: the static 'TOKS' holds an allocator, 'Comp' (in its type 'Vec<i64, Comp>'): a static's type may not hold one
try: volec refactor table TOKS --no-check
[exit 1]
$ fix --only unneeded-unsafe
note fix.none: nothing to fix
% "$COMPILER" main.vl -o b >/dev/null 2>&1 && ./b
4 10 36 40
2 8 23
100 297 411
5 100
3 7
$ check
base/mod.vl:4:5: warning[unsafe.unjustified] 22 unsafe sites lack `// UNSAFE:` and `// SAFETY:` comments (the first here) | help: each unsafe site says right above it why it cannot be safe and why it is sound; the try: line lists them | try: volec query unsafe --no-std --unjustified --root main.vl
ok: 0 errors, 1 warning in main.vl
