## fix --edition rust (0.27.5): a guarded match on a copy value read from
## a place is a match on the value, `match { c.kinds[i] } { .. }` (rustc
## E0502 otherwise: the guard's `&mut c` while the scrutinee's place is
## borrowed). Written, then built and run in the rust edition with the
## MVS program's output; the rustc twin agrees.
$ main.vl -o mvs
ok: built mvs
% ./mvs
b
a
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &mut T, 1 '&x' to '&mut x', 1 var to 'let mut', 1 import, 1 index cast to usize, 1 copy type derived Clone, Copy	main.vl	+6 -5 lines
% cat main.vl
// fix --edition rust (0.27.5): a match on a copy value read from a
// place, with a guard that changes the place's owner, matches the value
// (`match { c.kinds[i] } { .. }`): Rust keeps the scrutinee's place
// borrowed through the guards (rustc E0502).
use std::alloc::Allocator; #[derive(Clone, Copy, PartialEq, Eq)] enum K {
    A,
    B,
}

struct C<A: Allocator> {
    kinds: Vec<K, A>,
    n: i64,
}

fn bump(c: &mut C<Gpa>) -> bool {
    c.n += 1;
    c.n > 1
}

fn main(gpa: Gpa) {
    let mut c = C { kinds: Vec::new_in(gpa), n: 0 };
    c.kinds.push(K::B);
    c.kinds.push(K::A);
    for i in 0..2 {
        match { c.kinds[i as usize] } {
            K::A if bump(&mut c) => println("a {}", c.n),
            K::A => println("a"),
            K::B => println("b"),
        }
    }
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
b
a
