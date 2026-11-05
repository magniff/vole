## 0.27.0: `fix --only rawptr` takes a call given the context inside
## another call's arguments given it too (`put(cx, 0, get(cx, 1))`, where
## both inout would be own.conflict) into a let before the statement, with
## the arguments before it that read the context or call, in the order they
## ran; so too an argument nesting such calls (`twice(get(cx, put(cx, ..)))`),
## an if's condition and an operator's operands. A run that takes some
## decides no parameter; the next takes the calls nested in the lets' values
## in turn, and the one that takes none decides them (fix list item 12 of
## feedbacks/statics265.md). rawptr-list names the call that keeps a
## parameter raw for nested-call.
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
3 1 11 1 3 119
$ fix --only rawptr-list
main.vl:11	escape	nested-call	get	cx: *Ctx	big	at main.vl:64
main.vl:15	escape	nested-call	put	cx: *Ctx	big	at main.vl:42
main.vl:25	write	-	shuffle	cx: *Ctx	big
main.vl:40	write	-	sums	cx: *Ctx	big
main.vl:57	write	-	noted	cx: *Ctx	big
main.vl:63	write	-	guarded	cx: *Ctx	big
--- a/main.vl
+++ b/main.vl
@@ -26,3 +26,7 @@
-    put(cx, 0, get(cx, 1));
-    let x = put(cx, k + 1, get(cx, 2) * 2);
-    put(cx, get(cx, 3), get(cx, 4))
+    let get_v = get(cx, 1);
+    put(cx, 0, get_v);
+    let arg_v = get(cx, 2) * 2;
+    let x = put(cx, k + 1, arg_v);
+    let get_v1 = get(cx, 3);
+    let get_v2 = get(cx, 4);
+    put(cx, get_v1, get_v2)
@@ -33 +37,2 @@
-    put(&cx, 6, get(&cx, 7))
+    let get_v = get(&cx, 7);
+    put(&cx, 6, get_v)
@@ -42,2 +47,5 @@
-    vals[0] = twice(get(cx, put(cx, 1, k)));
-    if get(cx, 0) != get(cx, put(cx, 2, 3)) {
+    let get_v = get(cx, put(cx, 1, k));
+    vals[0] = twice(get_v);
+    let get_v1 = get(cx, 0);
+    let get_v2 = get(cx, put(cx, 2, 3));
+    if get_v1 != get_v2 {
@@ -47,3 +55,5 @@
-    let w = if k > 100 { 0 } else { twice(get(cx, put(cx, 4, 5) % 8)) };
-    let z = vals[get(cx, put(cx, 0, 1)) % 2];
-    vals[0] + vals[1] + twice(get(cx, put(cx, 3, 4) % 8)) + w + z
+    let w = if k > 100 { 0 } else { let get_v3 = get(cx, put(cx, 4, 5) % 8); twice(get_v3) };
+    let get_v4 = get(cx, put(cx, 0, 1));
+    let z = vals[get_v4 % 2];
+    let twice_v = twice(get(cx, put(cx, 3, 4) % 8));
+    vals[0] + vals[1] + twice_v + w + z
@@ -57,0 +68 @@
+    let get_v = get(cx, 0);
@@ -59 +70 @@
-    put(cx, 7, get(cx, 0))
+    put(cx, 7, get_v)
@@ -64 +75,2 @@
-    if put(cx, 5, get(cx, 6)) > 0 { 1 } else { 0 }
+    let put_v = put(cx, 5, get(cx, 6));
+    if put_v > 0 { 1 } else { 0 }
note fix.rawptr: raw pointer parameters: read 0 write 4 escape 2 caller 0 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 4 owned 0; reasons stored 0 returned 0 cast 0 compared 0 indexed 0 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 0 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 2; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 0; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 13
$ fix --only rawptr
fixed 13 nested calls taken into lets (run it again)	main.vl	+23 -11 lines
note fix.rawptr: raw pointer parameters: read 0 write 4 escape 2 caller 0 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 4 owned 0; reasons stored 0 returned 0 cast 0 compared 0 indexed 0 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 0 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 2; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 0; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 13
$ fix --only rawptr
fixed 6 nested calls taken into lets (run it again)	main.vl	+12 -6 lines
note fix.rawptr: raw pointer parameters: read 1 write 4 escape 1 caller 0 fixed 0; read by kind u8 0 copy 0 big 1 owned 0; write by kind u8 0 copy 0 big 4 owned 0; reasons stored 0 returned 0 cast 0 compared 0 indexed 0 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 0 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 1; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 0; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 6
$ fix --only rawptr
fixed 1 nested call taken into a let (run it again)	main.vl	+2 -1 lines
note fix.rawptr: raw pointer parameters: read 1 write 5 escape 0 caller 0 fixed 0; read by kind u8 0 copy 0 big 1 owned 0; write by kind u8 0 copy 0 big 5 owned 0; reasons stored 0 returned 0 cast 0 compared 0 indexed 0 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 0 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 0; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 0; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 1
$ fix --only rawptr
fixed 6 raw pointer parameters	main.vl	+27 -27 lines
note fix.rawptr: raw pointer parameters: read 1 write 5 escape 0 caller 0 fixed 0; read by kind u8 0 copy 0 big 1 owned 0; write by kind u8 0 copy 0 big 5 owned 0; reasons stored 0 returned 0 cast 0 compared 0 indexed 0 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 0 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 0; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 0; edits: to inout 6, to let 0, `&p` 22, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 0
$ fix --only rawptr
note fix.rawptr: raw pointer parameters: read 0 write 0 escape 0 caller 0 fixed 0; read by kind u8 0 copy 0 big 0 owned 0; write by kind u8 0 copy 0 big 0 owned 0; reasons stored 0 returned 0 cast 0 compared 0 indexed 0 to-raw 0 to-fn-value 0 captured 0 assigned 0 other 0 raw-arg 0 null-arg 0 through-raw-arg 0 other-arg 0 given-raw 0 nested-call 0; fixed unsafe-fn 0 exported 0 fn-value 0 main 0 closure 0 trait 0 nested 0 inout-ptr 0 receiver 0; calls giving no place 0; edits: to inout 0, to let 0, `&p` 0, `&x` to `x` 0, `*p` to `p` 0, `&*q` 0 (in a new unsafe block 0); nested calls taken into lets 0
note fix.none: nothing to fix
% "$COMPILER" main.vl -o a >/dev/null 2>&1 && ./a
3 1 11 1 3 119
% cat main.vl
// `volec fix --only rawptr`'s hoist (0.27.0, tests/refactor/rawptr0270.t):
// a call given the context inside another call's arguments that are given
// it too is taken into a let before the statement, so that both
// parameters can become inout.

struct Ctx {
    a: [i64; 8],
    n: i64,
}

fn get(cx: inout Ctx, i: i64) -> i64 {
    unsafe { cx.a[i] + cx.n }
}

fn put(cx: inout Ctx, i: i64, v: i64) -> i64 {
    unsafe {
        cx.a[i] = v;
        cx.n += 1;
        cx.n % 8
    }
}

// (a statement, a let's value, a block's value; an argument before the
// call that is not a name, taken into a let first)
fn shuffle(cx: inout Ctx, k: i64) -> i64 {
    let get_v = get(&cx, 1);
    put(&cx, 0, get_v);
    let arg_v = get(&cx, 2) * 2;
    let x = put(&cx, k + 1, arg_v);
    let get_v1 = get(&cx, 3);
    let get_v2 = get(&cx, 4);
    put(&cx, get_v1, get_v2)
}

// (an inout context's address stays in its place: the checker's `&*cx`)
fn again(cx: inout Ctx) -> i64 {
    let get_v = get(&cx, 7);
    put(&cx, 6, get_v)
}

// (a call nested in a call given another local, `twice(..)`; a
// place assigned that is not the context's, `vals[0] = ..`; an if's
// condition and an operator's operands, taken in order, but for what
// calls nothing and reads no context, `vals[0] + vals[1]`)
fn sums(cx: inout Ctx, k: i64) -> i64 {
    var vals: [i64; 2] = [0, 0];
    let put_v = put(&cx, 1, k);
    let get_v = get(&cx, put_v);
    vals[0] = twice(get_v);
    let get_v1 = get(&cx, 0);
    let put_v1 = put(&cx, 2, 3);
    let get_v2 = get(&cx, put_v1);
    if get_v1 != get_v2 {
        vals[1] = 1;
    }
    // (a block's value on the line of its `else {`; an index)
    let w = if k > 100 { 0 }
        else { let arg_v = put(&cx, 4, 5) % 8; let get_v3 = get(&cx, arg_v); twice(get_v3) };
    let put_v2 = put(&cx, 0, 1);
    let get_v4 = get(&cx, put_v2);
    let z = vals[get_v4 % 2];
    let arg_v1 = put(&cx, 3, 4) % 8;
    let get_v5 = get(&cx, arg_v1);
    let twice_v = twice(get_v5);
    vals[0] + vals[1] + twice_v + w + z
}

fn twice(v: i64) -> i64 {
    v * 2
}

// (the lets go above the comment right above the statement)
fn noted(cx: inout Ctx) -> i64 {
    let get_v = get(&cx, 0);
    // (says what the call does)
    put(&cx, 7, get_v)
}

// (an if's condition: taken into a let, as a statement's top)
fn guarded(cx: inout Ctx) -> i64 {
    let get_v = get(&cx, 6);
    let put_v = put(&cx, 5, get_v);
    if put_v > 0 { 1 } else { 0 }
}

fn main() {
    var c = Ctx { a: [1, 2, 3, 4, 5, 6, 7, 8], n: 0 };
    let s = shuffle(&c, 1);
    let g = guarded(&c);
    again(&c);
    let t = sums(&c, 7);
    noted(&c);
    println("{} {} {} {} {} {}", s, g, c.n, c.a[0], c.a[2], t);
}
