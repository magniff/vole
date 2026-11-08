## (0.28.0) A field of a reference type, MVS's `n: inout i64` (`&'a mut
## i64` in the rust edition), is written through with `*` where Rust does
## not dereference it itself: an assignment's target (`c.n += 10` ->
## `*c.n += 10`), a copy's read (`c.n * 2` -> `*c.n * 2`). 0.27.8 wrote
## the field as it was, a compound assignment to a `&mut i64` (a type
## error).
$ main.vl -o mvs
ok: built mvs
% ./mvs
7 34
$ fix --edition rust main.vl
fixed, 2 sink parameters to T, 1 receiver, 5 views to &[T], 1 '&x' to '&mut x', 5 accesses written '*r', 2 vars to 'let mut', 1 integer annotated	main.vl	+11 -10 lines
% cat main.vl
struct Counter<'a> { n: &'a mut i64, step: i64 }

impl<'a> Counter<'a> {
    fn tick(&mut self) {
        *self.n += self.step;
    }
}

fn bump(mut c: Counter<'_>) {
    *c.n += 10;
    *c.n = *c.n * 2;
}

fn main() {
    let mut x: i64 = 1;
    let mut c = Counter { n: &mut x, step: 3 };
    c.tick();
    c.tick();
    let seen = *c.n + 0;
    bump(c);
    println("{seen} {x}");
}
// EDITION: rust
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
7 34
