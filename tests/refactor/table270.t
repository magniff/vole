## 0.27.0: `volec refactor table` on a struct's field (fix list item 13 of
## feedbacks/statics265.md): `cx.items: *Item` with `cx.item_count` and
## `cx.item_cap` beside it in the struct becomes `cx.items: Vec<Item, A>`
## (A the struct's allocator parameter), `Vec::new_in(Comp {})` in its
## literal; the count's and the capacity's fields and initializers go, a
## grow and its store are a push, a read of the count `cx.items.len()`, a
## reset a clear.
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
5 30 1
$ refactor table Ctx.items --dry-run
--- a/main.vl
+++ b/main.vl
@@ -5 +4,0 @@
-use crate::base::grow;
@@ -12,5 +11 @@
-    pub items: *Item,
-    // (their count)
-    pub item_count: i64,
-    // (their capacity)
-    pub item_cap: i64,
+    pub items: Vec<Item, A>,
@@ -22,3 +17 @@
-        items: 0 as *Item,
-        item_count: 0,
-        item_cap: 0,
+        items: Vec::new_in(Comp {}),
@@ -31,2 +24 @@
-        cx.items = grow(cx.items, cx.item_count, &cx.item_cap);
-        cx.items[cx.item_count] = Item { v, next: cx.item_count + 1 };
+        cx.items.push(Item { v, next: cx.items.len() as i64 + 1 });
@@ -34,2 +26 @@
-    cx.item_count += 1;
-    cx.item_count - 1
+    cx.items.len() as i64 - 1
@@ -40 +31 @@
-    for i in 0..cx.item_count {
+    for i in 0..cx.items.len() as i64 {
@@ -47 +38 @@
-    cx.item_count = 0;
+    cx.items.clear();
@@ -58 +49 @@
-    println("{} {} {}", cx.item_count, total(cx), cx.other.len());
+    println("{} {} {}", cx.items.len() as i64, total(cx), cx.other.len());
$ refactor table Ctx.items
made crate::Ctx.items a Vec<Item, A>: 1 push, 4 len()s, 1 clear()	main.vl	+7 -16 lines
note refactor.table-unsafe: the unsafe blocks around its indexing may be unneeded now
try: volec fix --only unneeded-unsafe
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
5 30 1
## The unsafe blocks around the indexing are not needed now.
$ fix --only unneeded-unsafe
fixed 2 unneeded unsafe blocks	main.vl	+2 -4 lines
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
5 30 1
% cat main.vl
// refactor table on a context's field (tests/refactor/table270.t): a
// table kept in a struct as a raw pointer, a count and a capacity.
mod base;

use crate::base::comp::Comp;

struct Item { v: i64, next: i64 }

pub struct Ctx<A: Allocator> {
    // (the items)
    pub items: Vec<Item, A>,
    pub other: Vec<i64, A>,
}

fn ctx_new() -> Ctx<Comp> {
    Ctx {
        items: Vec::new_in(Comp {}),
        other: Vec::new_in(Comp {}),
    }
}

fn add_item(v: i64, cx: inout Ctx<Comp>) -> i64 {
    cx.items.push(Item { v, next: cx.items.len() as i64 + 1 });
    cx.items.len() as i64 - 1
}

fn total(cx: Ctx<Comp>) -> i64 {
    var t = 0;
    for i in 0..cx.items.len() as i64 {
        t += cx.items[i].v + cx.items[i].next;
    }
    t
}

fn reset(cx: inout Ctx<Comp>) {
    cx.items.clear();
}

fn main() {
    var cx = ctx_new();
    add_item(9, &cx);
    reset(&cx);
    for v in 1..6 {
        add_item(v, &cx);
    }
    cx.other.push(1);
    println("{} {} {}", cx.items.len() as i64, total(cx), cx.other.len());
}
