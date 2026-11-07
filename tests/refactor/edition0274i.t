## fix --edition rust (0.27.4, gate 3's elision wall): a result's views
## that Rust's elision cannot tie. With no parameter it could borrow from
## (an `&mut i64` out parameter is none) every view in the result is
## `'static` (`[&'static str; 2]`); with two or more and no `self`, the
## function gets `'a`, on the result's views and each parameter taken by
## a shared reference (`fn pick<'a>(a: &'a [u8], b: &'a [u8], ..) ->
## &'a [u8]`). Written, then built and run in the rust edition with the
## MVS program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
f 4 2
102 4 3
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &mut T, 13 views to &[T], 1 '&x' to '&mut x', 1 access written '*r', 1 var to 'let mut', 1 integer annotated, 3 text literals to bytes, 1 copy type derived Clone, Copy	main.vl	+11 -10 lines
% cat main.vl
// fix --edition rust (0.27.4, gate 3): a result's views where Rust's
// elision cannot tie them. No parameter to borrow from (an `inout i64`
// is none): `'static`, inside the result too (`[&'static str; 2]`). Two
// or more and no `self`: the function's `'a`, on the result's views and
// the parameters taken by a shared reference.
#[derive(Clone, Copy)] struct Opt<'a> { name: &'a str, help: &'a str }

fn flag<'a>(name: &'a str, help: &'a str) -> Opt<'a> {
    Opt { name: name, help: help }
}

fn tops() -> [&'static str; 2] {
    ["a", "bb"]
}

fn pick<'a>(a: &'a [u8], b: &'a [u8], first: bool) -> &'a [u8] {
    if first { a } else { b }
}

fn out(k: i64, n: &mut i64) -> &'static [u8] {
    *n = k;
    b"xyz"
}

fn main() {
    let o = flag("f", "help");
    let t = tops();
    let p = pick(b"ab", b"cde", false);
    let mut n: i64 = 0;
    let s = out(4, &mut n);
    let m = n;
    println("{} {} {}", o.name, o.help.len(), t[1].len());
    println("{} {} {}", p.len() + p[0] as usize, m, s.len());
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
f 4 2
102 4 3
