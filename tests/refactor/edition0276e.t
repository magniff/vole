## fix --edition rust (0.27.6): flip28's T3 and T4. hoist_read_index_edits:
## an index that calls with the indexed container's root `&mut` is
## computed first, around the element's first copied value; hoist_args:
## an argument that reads the root another argument gives as `&mut r` is
## read first (in a call of the program's own function); a block that
## would lead a statement is parenthesized. Written, formatted, then
## built and run in the rust edition with the MVS program's output; the
## rustc twin agrees (rust_t_hoist_read).
$ main.vl -o mvs
ok: built mvs
% ./mvs
94 9 8 6 56 true
$ fix --edition rust --list-left main.vl
fixed, 2 parameters to &mut T, 7 '&x's to '&mut x', 3 vars to 'let mut', 1 import, 5 indexes cast to usize, 1 copy type derived Clone, Copy	main.vl	+14 -13 lines
$ fmt main.vl
formatted	main.vl	+2 -1 lines
% cat main.vl
// fix --edition rust (0.27.6): a call's argument that reads the root
// another argument gives `&mut` is read first (rustc E0503 otherwise:
// the root used while mutably borrowed), and an index that calls with
// the indexed container's root `&mut` is computed first (rustc E0502:
// Index borrows the container before the index is computed).
use std::alloc::Allocator;

#[derive(Clone, Copy)] struct T {
    kind: i64,
    size: i64,
}

struct L<A: Allocator> {
    imports: Vec<i64, A>,
    types: Vec<T, A>,
    n: i64,
}

fn name(l: &mut L<Gpa>, s: i64) -> i64 {
    l.n += 1;
    s * 10 + l.n
}

fn pick(l: &mut L<Gpa>, k: i64) -> i64 {
    l.n += 1;
    k % l.types.len() as i64
}

// (a call that leads the block's value: the block parenthesized)
fn both(gpa: Gpa) -> bool {
    let mut l = L { imports: Vec::new_in(gpa), types: Vec::new_in(gpa), n: 0 };
    l.types.push(T { kind: 1, size: 2 });
    ({ let at_arg1 = l.n; name(&mut l, at_arg1) }) > 0
        && { let at_ix = pick(&mut l, 1) as usize; l.types[at_ix] }.size == 2
}

fn main(gpa: Gpa) {
    let mut l = L { imports: Vec::new_in(gpa), types: Vec::new_in(gpa), n: 0 };
    l.imports.push(4);
    l.imports.push(5);
    l.types.push(T { kind: 7, size: 8 });
    l.types.push(T { kind: 9, size: 16 });
    let mut total: i64 = 0;
    for i in 0..l.imports.len() as i64 {
        total += { let at_arg1 = l.imports[i as usize]; name(&mut l, at_arg1) };
    }
    let kind = { let at_ix = pick(&mut l, 3) as usize; l.types[at_ix] }.kind;
    let t = { let at_ix = pick(&mut l, 2) as usize; l.types[at_ix] };
    if l.n > 0 && { let at_ix = pick(&mut l, 5) as usize; l.types[at_ix] }.size != 0 {
        total += 1;
    }
    let last = { let at_arg1 = l.n; name(&mut l, at_arg1) };
    println("{} {} {} {} {} {}", total, kind, t.size, l.n, last, both(gpa));
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
94 9 8 6 56 true
