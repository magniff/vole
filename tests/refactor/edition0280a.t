## (0.28.0) An MVS std function whose every call a rewrite.tsv row writes
## as other names (`arena_scope(g, f)` -> `Arena::new_in(g).scope(..)`) is
## not imported: 0.27.7 imported `std::alloc::arena_scope` too, unused
## (use.unused, compiler/src's cli/build.vl and cli/run.vl). A type row's
## name (`Arena`) keeps its import.
$ main.vl -o mvs
ok: built mvs
% ./mvs
7
$ fix --edition rust main.vl
fixed, 1 var to 'let mut', 2 imports, 1 type, 1 std call by rewrite.tsv	main.vl	+5 -4 lines
% cat main.vl
use std::alloc::ArenaScope; use std::alloc::Arena; 

fn total(gpa: Gpa) -> i64 {
    Arena::new_in(gpa).scope(|s| ({ let a = s; {
        let mut v: Vec<i64, &ArenaScope<'_, Gpa>> = Vec::new_in(a);
        v.push(3);
        v.push(4);
        v[0] + v[1]
    } }))
}

fn main(gpa: Gpa) {
    println("{}", total(gpa));
}
// EDITION: rust
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
7
