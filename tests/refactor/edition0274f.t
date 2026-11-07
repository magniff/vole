## fix --edition rust (0.27.4, gate 3's next walls): an address cast to
## another pointee by `&raw const`/`&raw mut` (Rust casts no `&mut i64`
## to a `*mut f64`), `&p[i]` of a raw pointer as `p.add(i)` (not a
## reference), a copied type's inherent receiver by value (`self == Call`
## and `self as i64` of an `&self` are a reference's), `: i64` on a let of
## an `if` with a literal branch, and a suffix on an i64 literal outside
## i32 under a cast (`u64` above i64::MAX: MVS's bits). Written, then
## built and run in the rust edition with the MVS program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
4607182418800017408 7 4
false 3 3087007745 6148914691236517205 705032704
$ fix --edition rust --list-left main.vl
fixed, 2 '&x's to '&mut x', 2 vars to 'let mut', 6 integers annotated, 4 types, 2 indexes cast to usize, 1 copy type derived Clone, Copy	main.vl	+14 -13 lines
% cat main.vl
// fix --edition rust (0.27.4, gate 3): a local's address cast to another
// pointee is `&raw const x as *mut U` (`&raw mut` for a var), a raw
// pointer's element address `&p[i]` is `p.add(i)`, an inherent method's
// receiver of a type MVS copies is `self`, an unannotated let of an `if`
// with a literal branch is `: i64`, and an i64 literal outside i32 under
// a cast gets a suffix.
extern "C" {
    fn strlen(p: *mut u8) -> u64;
}

#[derive(Clone, Copy, PartialEq, Eq)] enum Op { Call, Plus, Ret }

impl Op {
    fn is_call(self) -> bool {
        self == Op::Call || self as i64 == 5
    }
}

fn bits_of(value: f64) -> i64 {
    let copy = value;
    // UNSAFE: a test. SAFETY: copy is 8 bytes.
    unsafe { *(&raw const copy as *mut i64) }
}

fn main() {
    let mut x: i64 = 0;
    // UNSAFE: a test. SAFETY: x is 8 bytes, its first one written.
    unsafe { *(&raw mut x as *mut u8) = 7; }
    let s = c"hello" as *mut u8;
    // UNSAFE: a test. SAFETY: s has 6 bytes.
    let rest = unsafe { s.add(1) };
    // UNSAFE: a test. SAFETY: rest is a C string.
    let n = unsafe { strlen(rest) };
    let c = std::env::args().count() > 5;
    let np: i64 = 3;
    let e0: i64 = if c { 1 } else { 0 };
    let mut sum: i64 = 0;
    for i in e0..np {
        sum += i;
    }
    let base: i64 = if c { 1 } else { 0xb8000000 };
    let m = 0xffffffffffffffffu64 as u64 / 3;
    let w = 5000000000i64 as i32;
    println("{} {} {}", bits_of(1.0), x, n);
    println("{} {} {} {} {}", Op::Plus.is_call(), sum, base + 1, m, w);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
4607182418800017408 7 4
false 3 3087007745 6148914691236517205 705032704
