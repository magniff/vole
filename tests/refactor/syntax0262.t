## 0.26.2: `where` and argument-position `impl Trait` (tests/refactor/syntax0262/):
## fmt spaces them as it does inline bounds, breaks a long `where` after a
## comma as a continuation, puts a `where` of its own line one level in
## and its predicates two, and the body's `{` at the signature's level.
$ fmt
formatted	main.vl	+8 -6 lines
% cat main.vl
use std::fmt::Display;

fn show<T>(x: T, y: impl Display) where T: Display + Copy, {
    println("{x} {y}");
}

#[derive(Clone, Copy)] struct Pair<A, B> where A: Display, B: Display { a: A, b: B }

fn long_one<Aaaaaaaaaaa, Bbbbbbbbbbbbb, Cccccccccccc>(a: &Aaaaaaaaaaa, b: &Bbbbbbbbbbbbb,
    c: &Cccccccccccc) -> i64 where Aaaaaaaaaaa: Display, Bbbbbbbbbbbbb: Display + Copy,
    Cccccccccccc: Copy {
    0
}

fn own_line<T, U>(x: T, u: &U)
    where
        T: Display,
        U: Copy,
{
    println("{x}");
}

fn main() -> i32 {
    show(1i64, "a");
    own_line(2i64, &3i64);
    let p = Pair { a: 1i64, b: 2i64 };
    println("{}", p.a);
    long_one(&1i64, &2i64, &3i64) as i32
}
// EDITION: rust
$ fmt
note fmt.none: 1 file formatted already
$ check
ok: 0 errors in main.vl
