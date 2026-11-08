## (0.28.0) Two more `[u8]` values printed as text get
## `str::from_utf8(..).unwrap()` (Rust's [u8] has no Display): what a
## function written `-> Option<[u8]>` gives unwrapped (`{a}` of `let a =
## shown(n).unwrap()`), and an element of a Vec of bytes taken by std's
## `get`, `first`, `last` or `pop` (`keep.get(0)`, which is `keep[0usize]`
## now), as an index of one was already. 0.27.8 left both as they were,
## a `&[u8]` in a Display hole (a type error).
$ main.vl -o mvs
ok: built mvs
% ./mvs
vole vo vol
$ fix --edition rust main.vl
fixed, 2 parameters to &T, 5 views to &[T], 3 borrows written '&x', 1 var to 'let mut', 2 integers annotated, 4 text literals to bytes, 2 std calls by rewrite.tsv, 2 indexes cast to usize, 3 byte views printed as text by str::from_utf8, 1 copy type derived Clone, Copy	main.vl	+10 -9 lines
% cat main.vl
#[derive(Clone, Copy)] struct Name { bytes: [u8; 8], len: i64 }

fn shown(n: &Name) -> Option<&[u8]> { if n.len > 0 { Some(&n.bytes[..n.len as usize]) } else { None } }

fn part(n: &Name, k: i64) -> &[u8] { &n.bytes[..k as usize] }

fn main(gpa: Gpa) {
    let n = Name { bytes: [b'v', b'o', b'l', b'e', 0, 0, 0, 0], len: 4 };
    let a = shown(&n).unwrap();
    let mut keep: Vec<&[u8], Gpa> = Vec::new_in(gpa);
    keep.push(part(&n, 2));
    keep.push(part(&n, 3));
    println("{a} {} {}", str::from_utf8(keep[0usize]).unwrap(), str::from_utf8(keep[1usize]).unwrap(), a = str::from_utf8(a).unwrap());
}
// EDITION: rust
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
vole vo vol
