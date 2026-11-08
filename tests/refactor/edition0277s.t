## fix --edition rust (0.27.7): static_returns' forwarders and tuple parts.
## A call of a function every result of which is a part of one view
## parameter, given a static value there (`base_name("Vec<i64>")`), is
## static; so is a local bound in a tuple pattern each of whose values is
## (`let (text, m) = if .. { ("len()", 1) } ..`). Written, then built and
## run in the rust edition with the MVS program's output (elided, the
## results would be tied to `w`: a borrowck.conflict); the rustc twin
## agrees (rust_t_static_parts).
$ main.vl -o mvs
ok: built mvs
% ./mvs
3 10 1 1
$ fix --edition rust --list-left main.vl
fixed, 2 parameters to &T, 5 views to &[T], 2 borrows written '&x', 2 vars to 'let mut', 3 '.len's to '.len()', 1 integer annotated, 1 import, 5 text literals to bytes, 2 indexes cast to usize	main.vl	+16 -15 lines
$ fmt main.vl
note fmt.none: 1 file formatted already
% cat main.vl
// fix --edition rust (0.27.7): two more static values (static_returns).
// A call of a function every result of which is a part of one view
// parameter, given a static value there (`base_name("Vec<i64>")`), and
// a part of a tuple pattern each of whose values is static (`let (text,
// m) = if .. { ("len()", 1) } ..`): `name` and `pick` return `&'static`,
// so main may change `w` while it holds their results.
use std::alloc::Allocator;

struct W<A: Allocator> {
    v: Vec<i64, A>,
    n: i64,
}

fn base_name(n: &[u8]) -> &[u8] {
    let mut k: i64 = 0;
    while k < n.len() as i64 && n[k as usize] != b'<' {
        k += 1;
    }
    &n[0..k as usize]
}

fn name(w: &W<Gpa>) -> &'static [u8] {
    if w.n < 0 {
        return b"";
    }
    base_name(b"Vec<i64>")
}

fn pick(w: &W<Gpa>, k: i64) -> &'static [u8] {
    let (text, m) = if k == 0 { ("len()", 1) } else if k == 1 { ("capacity()", 2) }
        else { ("", 0) };
    if m == 0 || w.n < 0 {
        return b"";
    }
    text.as_bytes()
}

fn main(gpa: Gpa) {
    let mut w: W<Gpa> = W { v: Vec::new_in(gpa), n: 0 };
    let a = name(&w);
    let b = pick(&w, 1);
    w.n += 1;
    w.v.push(w.n);
    println("{} {} {} {}", a.len(), b.len(), w.n, w.v.len());
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
3 10 1 1
