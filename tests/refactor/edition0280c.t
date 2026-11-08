## (0.28.0) An integer MVS widened implicitly from a value whose type the
## rust edition fixes too (a byte read, a call's u32, u8 locals) is written
## `as T` (rustc's E0308 otherwise): `h ^= bytes[i] as u64`; a literal tree
## is not (the rust edition infers it), nor an index (cast to usize).
$ main.vl -o mvs
ok: built mvs
% ./mvs
103 97 16 8
$ fix --edition rust main.vl
fixed, 1 view to &[T], 1 var to 'let mut', 1 '.len' to '.len()', 1 text literal to bytes, 5 widenings written 'as T'	main.vl	+8 -7 lines
% cat main.vl
fn bits(x: u32) -> u32 {
    x * 3
}

fn take(v: u64) -> u64 {
    v + 1
}

fn main() {
    let bytes: &[u8] = b"abc";
    let mut h: u64 = 7;
    for i in 0..bytes.len() {
        h ^= bytes[i] as u64;
    }
    let n: i64 = 2;
    let w: i64 = if n > 1 { bytes[0] as i64 } else { 0 };
    let k = take(bits(5) as u64);
    let s: u8 = 3;
    let t: u8 = 4;
    let u = take(s as u64 + t as u64);
    println("{} {} {} {}", h, w, k, u);
}
// EDITION: rust
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
103 97 16 8
