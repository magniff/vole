## fix --edition rust (0.27.5, F0.6): the rust edition reads no `&str` as
## a `&[u8]` (rustc E0308). A literal whose value goes where bytes are
## declared is `b".."` (`s == ".vl"` of an `s: [u8]`, an `if` branch, an
## array's element, a field, an assignment, a match arm, a tuple's part);
## a value declared text given there is `x.as_bytes()` (a `str` binding,
## a local of literals, an element of a local array of them, a tuple
## pattern's). Written, then built and run in the rust edition with the
## MVS program's output; tests/run/rust_t_f06_text_bytes is the
## translation, which the rustc twin builds and runs.
$ main.vl -o mvs
ok: built mvs
% ./mvs
3 4 1 2 4
5 4 2 2
7 4 8 109
$ fix --edition rust --list-left main.vl
fixed, 12 views to &[T], 2 vars to 'let mut', 21 text literals to bytes, 1 copy type derived Clone, Copy	main.vl	+25 -24 lines
% cat main.vl
// fix --edition rust (0.27.5, F0.6): `&str` is no `&[u8]` in the rust
// edition, as in Rust. A text literal whose value goes where bytes are
// declared is `b".."`: compared with bytes, an `if` branch, an array's
// element, a field, an assignment, a match arm, a tuple's part. A value
// declared text given there is `.as_bytes()`: a `str` binding, a local
// of literals, an element of a local array of them, a tuple pattern's.
#[derive(Clone, Copy)] struct Help<'a> {
    cmd: &'a [u8],
    n: i64,
}

fn count(b: &[u8]) -> i64 {
    b.len() as i64
}

fn kind(k: i64) -> &'static [u8] {
    match k {
        0 => b"zero",
        _ => b"many",
    }
}

fn pair(c: bool) -> (&'static [u8], i64) {
    if c { (b"yes", 1) } else { (b"no", 0) }
}

fn word(c: bool) -> (&'static [u8], i64) {
    let (w, n) = if c { ("long", 4) } else { ("", 0) };
    if n > 0 { (w.as_bytes(), n) } else { (b"none", 0) }
}

fn main() {
    let c = std::env::args().count() > 5;
    let path: &[u8] = b"main.vl";
    let name: &str = "text";
    let open: &[u8] = if c { b"" } else if path.len() > 20 { b"[" } else { b"(" };
    let list: [&[u8]; 2] = [b"b", b"cd"];
    let mut head: &[u8] = b"x";
    head = b"head";
    let h = Help { cmd: b"help", n: 1 };
    let m = if c { "7" } else { "15" };
    let kws = ["fn ", "struct "];
    let mut hits: i64 = 0;
    if &path[path.len() - 3..] == b".vl" {
        hits += 1;
    }
    if path != b"other.vl" {
        hits += 1;
    }
    if path.ends_with(b".vl") {
        hits += 1;
    }
    let (p, pn) = pair(!c);
    let (w, wn) = word(!c);
    println("{} {} {} {} {}", hits, count(name.as_bytes()), count(open), list.len(), count(head));
    println("{} {} {} {}", count(h.cmd) + h.n, count(kind(0)), count(list[1]), count(m.as_bytes()));
    println("{} {} {} {}", count(kws[1].as_bytes()), count(p) + pn, count(w) + wn, path[0] as i64);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
3 4 1 2 4
5 4 2 2
7 4 8 109
