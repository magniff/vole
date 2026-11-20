## XFAIL: RT-192: an inherent method beside a trait impl's method of its name cannot be named: `crate::U::m` is `query.ambiguous`, and its own `try:` repeats `crate::U::m` (0.30.2)
## U has an inherent `fn m` and `impl A for U { fn m }`. `refactor rename
## U::m zz` says `error query.ambiguous: 2 definitions match 'U::m'; name
## one` and offers `try: ... '<crate::U as A>::m' zz` and `try: ...
## crate::U::m zz`; the second gives the same error and the same two
## tries. The trait's is `<crate::U as A>::m`, so `crate::U::m` names the
## inherent one (rustc's path rule: an inherent item first). Only a
## FILE:LINE reaches it today (main.vl:14:8 renames it rightly: 3 lines).
## query show crate::U::m shows the other one, `<crate::U as A>::m` (100),
## and query refs crate::U::m lists both items' definitions.
$ refactor rename crate::U::m zz
renamed crate::U::m to zz	main.vl	+3 -3 lines
% cat main.vl
trait A {
    fn m(&self) -> i64;
}

struct U;

impl A for U {
    fn m(&self) -> i64 {
        100
    }
}

impl U {
    fn zz(&self) -> i64 {
        1000
    }
}

fn main() {
    let u = U;
    let g: fn(&U) -> i64 = U::zz;
    println("{} {} {} {}", u.zz(), U::zz(&u), g(&u), (&u).zz());
}
