## 0.25.4: `volec refactor table X` (tests/refactor/table254/): a table
## kept as a raw pointer, a count and a capacity becomes a Vec<T, Comp>;
## every use is placed, or the refactor is refused and changes nothing.
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
4 10 36 40
2 8 23
100 297 411
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
@@ -30 +30 @@
-    println(f"{ITEM_COUNT} {total()} {crate::items::PLACES} {crate::count::count()}");
+    println(f"{ITEMS.len()} {total()} {crate::items::PLACES} {crate::count::count()}");
--- a/count.vl
+++ b/count.vl
@@ -2 +1,0 @@
-use crate::items::ITEM_COUNT;
@@ -3,0 +3,2 @@
+use crate::items::ITEMS;
+
@@ -5 +6 @@
-    ITEM_COUNT * 10
+    ITEMS.len() * 10
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
+        ITEMS.push(Item { v, next: ITEMS.len() + 1 });
+        PLACES += (ITEMS.len() - 1) * 2 + ITEMS.len();
@@ -22,2 +20 @@
-    ITEM_COUNT += 1;
-    ITEM_COUNT - 1
+    ITEMS.len() - 1
@@ -29,4 +26,2 @@
-        ITEMS = grow(ITEMS, ITEM_COUNT, &ITEM_CAP);
-        let n = ITEM_COUNT;
-        ITEMS[n] = Item { v, next: -1 };
-        ITEM_COUNT += 1;
+        let n = ITEMS.len();
+        ITEMS.push(Item { v, next: -1 });
@@ -38 +33 @@
-    ITEM_COUNT = 0;
+    ITEMS.clear();
@@ -42 +37 @@
-    ITEM_COUNT -= k;
+    ITEMS.truncate(ITEMS.len() - k);
@@ -46 +41 @@
-    ITEM_COUNT -= k - 1;
+    ITEMS.truncate(ITEMS.len() - (k - 1));
@@ -51 +46 @@
-    for i in 0..ITEM_COUNT {
+    for i in 0..ITEMS.len() {
--- a/report.vl
+++ b/report.vl
@@ -2 +2 @@
-use crate::items::{ITEMS, ITEM_COUNT};
+use crate::items::ITEMS;
@@ -6 +6 @@
-    for i in 0..ITEM_COUNT {
+    for i in 0..ITEMS.len() {
@@ -9 +9 @@
-    s + crate::items::ITEM_COUNT * 100 + unsafe { crate::items::ITEMS[0].v }
+    s + crate::items::ITEMS.len() * 100 + unsafe { crate::items::ITEMS[0].v }
note edit.imports: added the imports the new text needs (fix --only imports)
## The increment before the store (at a local set before it): reads
## between them one more.
$ refactor table MARKS --dry-run
--- a/main.vl
+++ b/main.vl
@@ -31 +31 @@
-    println(f"{crate::marks::MARK_COUNT} {last()} {crate::marks::seen(1)}");
+    println(f"{crate::marks::MARKS.len()} {last()} {crate::marks::seen(1)}");
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
+        let id = MARKS.len();
+        let seen = MARKS.len() + (MARKS.len() + 1) * 10;
+        MARKS.push(Mark { at, seen: seen + (MARKS.len() + 1) });
@@ -25 +22 @@
-    unsafe { MARKS[MARK_COUNT - 1].at }
+    unsafe { MARKS[MARKS.len() - 1].at }
note edit.imports: added the imports the new text needs (fix --only imports)
## A grow in `if TOK_COUNT >= TOK_CAP { ... }`: the `if` goes with it;
## `TOKS = reserve(TOKS, &TOK_CAP, n)` (room for n in all) is a Vec's
## reserve of what is missing.
$ refactor table TOKS --dry-run
--- a/main.vl
+++ b/main.vl
@@ -13 +13 @@
-use crate::tokens::{TOK_COUNT, add_tok, reserve_toks};
+use crate::tokens::{TOKS, add_tok, reserve_toks};
@@ -32 +32 @@
-    println(f"{TOK_COUNT} {crate::tokens::tok(99)} {crate::report::report()}");
+    println(f"{TOKS.len()} {crate::tokens::tok(99)} {crate::report::report()}");
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
+    TOKS.reserve(n + 1 - TOKS.len());
@@ -15,4 +14 @@
-        if TOK_COUNT >= TOK_CAP {
-            TOKS = grow(TOKS, TOK_COUNT, &TOK_CAP);
-        }
-        TOKS[TOK_COUNT] = t * 3;
+        TOKS.push(t * 3);
@@ -20 +15,0 @@
-    TOK_COUNT += 1;
note edit.imports: added the imports the new text needs (fix --only imports)
## Refused, each use listed: a pointer into the table, the table passed
## and assigned, the capacity read, the count written, a call between the
## store and its increment that reads the count.
$ refactor table BADS
error refactor.table-use: crate::refused::BADS: 6 uses refactor table cannot place; nothing changed
refused.vl:24:9: `noted()`: a call between the store and `BAD_COUNT += 1` reaches code naming BAD_COUNT (it would see the count changed): move the `+= 1` next to the store first
refused.vl:27:19: `&BADS[0]`: a pointer into the table (`&BADS[i]`): kept past a push it dangles; take the index, or the element by value
refused.vl:31:5: `BAD_COUNT = n`: BAD_COUNT written (a Vec's length changes by push, clear and truncate only)
refused.vl:35:5: `BAD_CAP - BAD_COUNT`: BAD_CAP read outside the grow (a Vec's capacity is its own)
refused.vl:40:14: `BADS as *u8`: the table itself used (passed, assigned, compared, freed): a Vec is not its pointer
refused.vl:42:5: `BADS = 0 as *Bad`: the table itself used (passed, assigned, compared, freed): a Vec is not its pointer
note refactor.table-why: 1: a call between the store and `BAD_COUNT += 1` reaches code naming BAD_COUNT (it would see the count changed): move the `+= 1` next to the store first
note refactor.table-why: 1: a pointer into the table (`&BADS[i]`): kept past a push it dangles; take the index, or the element by value
note refactor.table-why: 2: the table itself used (passed, assigned, compared, freed): a Vec is not its pointer
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
made crate::items::ITEMS a Vec<Item, Comp>: 2 pushes, 10 len()s, 1 clear(), 2 truncate()s	4 files	+20 -24 lines
note edit.imports: added the imports the new text needs (fix --only imports)
note refactor.table-unsafe: the unsafe blocks around its indexing may be unneeded now
try: volec fix --only unneeded-unsafe
$ refactor table MARKS
made crate::marks::MARKS a Vec<Mark, Comp>: 1 push, 6 len()s	2 files	+8 -11 lines
note edit.imports: added the imports the new text needs (fix --only imports)
note refactor.table-unsafe: the unsafe blocks around its indexing may be unneeded now
try: volec fix --only unneeded-unsafe
$ refactor table TOKS
made crate::tokens::TOKS a Vec<i64, Comp>: 1 push, 1 len(), 1 reserve()	2 files	+7 -12 lines
note edit.imports: added the imports the new text needs (fix --only imports)
note refactor.table-unsafe: the unsafe blocks around its indexing may be unneeded now
try: volec fix --only unneeded-unsafe
$ fix --only unneeded-unsafe
fixed 10 unneeded unsafe blocks	4 files	+16 -24 lines
% "$COMPILER" main.vl -o b >/dev/null 2>&1 && ./b
4 10 36 40
2 8 23
100 297 411
3 7
$ check
base/mod.vl:4:5: warning[unsafe.unjustified] 11 unsafe sites lack `// UNSAFE:` and `// SAFETY:` comments (the first here) | help: each unsafe site says right above it why it cannot be safe and why it is sound; the try: line lists them | try: volec query unsafe --no-std --unjustified --root main.vl
ok: 0 errors, 1 warning in main.vl
