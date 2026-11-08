## (0.28.0) A write into a part of a static is made on a copy only where
## the copy is proven the static's only view while it lives (statics.vl:
## prove_copies): nothing evaluated there, nor a function called there
## or one it calls, touches the same static. `TALLY.n = next() + 10`
## calls next(), which writes TALLY: on a copy taken before it, that
## write is lost (`11 0`), so the place is written in place through the
## static's raw address, in unsafe code without UNSAFE:/SAFETY: lines,
## and left to hand: `11 1`, as MVS. (A static lent to a call that reads
## it by name is MVS's own.static error, so `f(&V)` is proven when f is
## known.)
$ main.vl -o mvs
ok: built mvs
% ./mvs
11 1
$ fix --edition rust --list-left main.vl
fixed, 1 parameter to &mut T, 1 '&x' to '&mut x', 1 static var to 'static mut', 6 static uses through their accessors, 1 copy type derived Clone, Copy	main.vl	+24 -8 lines
note fix.edition_left: main.vl:22:5: a static's part written in place, through its raw address: a copy of it could miss a read or write of it there (check that nothing there touches the static, then justify the unsafe): TALLY
note fix.edition_left: 1 left to hand (--list-left lists them): 1 a static's part written in place, through its raw address: a copy of it could miss a read or write of it there (check that nothing there touches the static, then justify the unsafe);
% cat main.vl
#[derive(Clone, Copy)] struct Tally {
    n: i64, seen: i64,
}

static mut TALLY: Tally = Tally { n: 0, seen: 0 };

// writes TALLY itself: a copy of TALLY made around a call of it would
// lose that write
fn next() -> i64 {
    { let mut tally_copy = get_tally(); tally_copy.seen += 1; set_tally(tally_copy); }
    get_tally().seen
}

fn bump(t: &mut Tally) {
    t.n += 1;
}

fn main() {
    // (proven: bump does not touch TALLY)
    { let mut tally_copy = get_tally(); bump(&mut tally_copy); set_tally(tally_copy); }
    // (not proven: next writes TALLY while the assignment's copy would live)
    unsafe { (*tally_ptr()).n = next() + 10; }
    println("{} {}", get_tally().n, get_tally().seen);
}

// (0.28.0) TALLY's accessors: every use of it is one of them.
fn get_tally() -> Tally {
    unsafe { TALLY }
}

fn set_tally(v: Tally) {
    unsafe {
        TALLY = v;
    }
}

fn tally_ptr() -> *mut Tally {
    &raw mut TALLY
}
// EDITION: rust
$ check main.vl
main.vl:22:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:28:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:32:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
ok: 0 errors, 3 warnings in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
11 1
