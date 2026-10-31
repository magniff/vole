## 0.26.2: `where` and argument-position `impl Trait` (tests/refactor/syntax0262/):
## fmt spaces them as it does inline bounds, breaks a long `where` after a
## comma as a continuation, puts a `where` of its own line one level in
## and its predicates two, and the body's `{` at the signature's level.
$ fmt
formatted	main.vl	+8 -6 lines
% cat main.vl
use std::Display;

fn show<T>(x: T, y: impl Display) where T: Display + Copy, {
    println(f"{x} {y}");
}

struct Pair<A, B> where A: Display, B: Display { a: A, b: B }

fn long_one<Aaaaaaaaaaa, Bbbbbbbbbbbbb, Cccccccccccc>(a: Aaaaaaaaaaa, b: Bbbbbbbbbbbbb,
    c: Cccccccccccc) -> i64 where Aaaaaaaaaaa: Display, Bbbbbbbbbbbbb: Display + Copy,
    Cccccccccccc: Copy {
    0
}

fn own_line<T, U>(x: T, u: U)
    where
        T: Display,
        U: Copy,
{
    println(f"{x}");
}

fn main() -> i32 {
    show(1, "a");
    own_line(2, 3);
    let p = Pair { a: 1, b: 2 };
    println(f"{p.a}");
    long_one(1, 2, 3) as i32
}
$ fmt
note fmt.none: 1 file formatted already
$ check
ok: 0 errors in main.vl
$ explain where.unsupported
where.unsupported: error
(0.26.2) A `where` predicate whose left side is not a type parameter of the item: `where I::Item: Display`, `where Vec<T>: Debug`. In 0.26 `where` is another way to write a parameter's bounds, `fn f<T>(x: T) where T: Display` is `fn f<T: Display>(x: T)`; a bound on any other type comes with the rust edition. The predicate is left out.
fix: Bound a parameter instead: for an iterator's items, a parameter for the item type, `I: Iterator<Item = X>, X: Display`.
example:
    error[where.unsupported] 'I::Item: Display': a 'where' bound is on a type parameter of the item, and 'I::Item' is not one | help: a bound on a type that is not a parameter comes with the rust edition; bound a parameter instead: 'I: Iterator<Item = X>, X: Display'
$ explain type.impl-position
type.impl-position: error
(0.26.2) `impl Trait` outside a function's parameter: in a result (`-> impl Display`), a field, a `let`, a type alias. A parameter's `x: impl Display` is a hidden type parameter of the function, `fn f<T: Display>(x: T)`, that each call infers; a result's `impl Trait` (a type the function picks and hides) comes with the rust edition.
fix: Name a type parameter, or write the type itself: `fn f() -> i64`; for a closure, a result of a named type (`Vec`, a struct) or a parameter the caller passes.
example:
    error[type.impl-position] 'impl Display' is a parameter's type only, in this release | help: name a type parameter instead, 'fn f<T: Display>() -> T'; 'impl Trait' in a result, a field or a 'let' comes with the rust edition
