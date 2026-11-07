## fix --edition rust (0.27.4, gate 3's fourth wall): rewrite.tsv's type
## rows (`Arena` -> `Arena<Gpa>`, `thread::JoinHandle<T>` ->
## `JoinHandle<T, Gpa>`), applied where the type is written, its arguments
## kept, the names the row writes imported (a path's segment does not
## count as the file naming one); `$a` with no allocator argument is the
## enclosing function's `Gpa` parameter (`thread::spawn(f)` ->
## `thread::spawn_in(f, gpa)`). Written, then built and run in the rust
## edition with the MVS program's output.
$ fix --edition rust --list-left main.vl
fixed, 2 parameters to &mut T, 2 '&x's to '&mut x', 3 vars to 'let mut', 3 imports, 4 types, 4 std calls by rewrite.tsv, 1 copy type derived Clone, Copy	main.vl	+11 -10 lines
% cat main.vl
// fix --edition rust (0.27.4, gate 3's fourth wall): rewrite.tsv's type
// rows where an MVS std type is written (`Arena` is `Arena<Gpa>`,
// `thread::JoinHandle<i64>` `JoinHandle<i64, Gpa>`, imported); a row's
// `$a` with no allocator given is the one in scope (`thread::spawn(f)`
// is `thread::spawn_in(f, gpa)`).
use std::thread::JoinHandle; use std::alloc::Allocator; use std::alloc::Arena; use std::thread;

#[derive(Clone, Copy)] pub struct Cx<W: Allocator> {
    pub arena: W,
}

fn init(gpa: Gpa, cx: &mut Cx<Arena<Gpa>>) {
    cx.arena = Arena::with_capacity_in(0 as usize, gpa);
}

fn work(gpa: Gpa, cx: &mut Cx<Arena<Gpa>>) -> i64 {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(4);
    v.push(5);
    v[0] + v[1]
}

fn main(gpa: Gpa) {
    let mut cx: Cx<Arena<Gpa>> = Cx { arena: Arena::new_in(gpa) };
    init(gpa, &mut cx);
    let h: JoinHandle<i64, Gpa> = thread::spawn_in(move || { 7 }, gpa);
    println("{} {}", work(gpa, &mut cx), h.join().unwrap());
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
9 7
