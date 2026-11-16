## XFAIL: RT-191: refactor rename of a trait method leaves its path uses (`A::m(&s)`, `<S as A>::m(&s)`, the fn value `<S as A>::m`), so the rename is refused as breaking the program (0.30.2)
## `refactor rename A::m mm` renames the trait's declaration, the impl's
## method and the method call `s.m()`, and nothing else: the path call
## `A::m(&s)`, the qualified call `<S as A>::m(&s)` and the fn value
## `let f: fn(&S) -> i64 = <S as A>::m;` keep `m`, so the edit check finds
## `no associated function 'm' in 'S'` (15:28) and `no method 'm' on type
## 'S'` (16:36) and writes nothing. query refs lists these uses (as
## `<S as A>::m`), so the rename's set is not refs'. A rename that fits
## every use is wanted; the output line's exact counts are the fixer's.
## v0.28.0, v0.29 and v0.30.1 the same.
$ refactor rename A::m mm
renamed crate::A::m to mm	main.vl	+4 -4 lines
% cat main.vl
trait A {
    fn mm(&self) -> i64;
}

struct S;

impl A for S {
    fn mm(&self) -> i64 {
        1
    }
}

fn main() {
    let s = S;
    let f: fn(&S) -> i64 = <S as A>::mm;
    println("{} {} {} {}", s.mm(), A::mm(&s), <S as A>::mm(&s), f(&s));
}
