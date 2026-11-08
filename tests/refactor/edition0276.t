## fix --edition rust (0.27.6): an argument given to a parameter taken
## `&mut` is `&mut`, whatever it views (a part of an inout array, of a
## Vec, of a local), given to an `inout [u32]` or to std::arch's `&mut
## [u32]` (rustc E0308: the types differ in mutability; link_macho's
## `vst1q_u32(&h[..], ..)`). Written, then built and run in the rust
## edition with the MVS program's output (std::arch's API is vole's: no
## rustc twin).
$ main.vl -o mvs
ok: built mvs
% ./mvs
2 5 2 5 3 11 22 31
$ fix --edition rust --list-left main.vl
fixed, 3 parameters to &mut T, 3 views to &[T], 13 '&x's to '&mut x', 3 vars to 'let mut', 1 import, 1 index cast to usize	main.vl	+24 -23 lines
% cat main.vl
// fix --edition rust (0.27.6): an argument given to a parameter taken
// `&mut` is `&mut`, whatever it views: a part of an inout array, of a
// Vec or of a local, given to an `inout [u32]` or to std::arch's `&mut
// [u32]` (rustc E0308: the types differ in mutability).
use std::arch::aarch64::vld1q_u32; use std::arch::aarch64::vst1q_u32;

fn bump(s: &mut [u32], i: i64) {
    s[i as usize] += 1;
}

fn by_param(h: &mut [u32; 8]) {
    bump(&mut h[..], 0);
    bump(&mut h[2..4], 1);
    let v = vld1q_u32(&h[..], 0);
    vst1q_u32(&mut h[..], 4, v);
}

fn by_vec(v: &mut Vec<u32, Gpa>) {
    bump(&mut v[..], 1);
    bump(&mut v[1..3], 0);
    let w = vld1q_u32(&v[..], 0);
    vst1q_u32(&mut v[..], 0, w);
}

fn main(gpa: Gpa) {
    let mut h: [u32; 8] = [1, 2, 3, 4, 5, 6, 7, 8];
    by_param(&mut h);
    let mut a: [u32; 4] = [0, 0, 0, 0];
    bump(&mut a[..], 3);
    bump(&mut a[1..3], 1);
    vst1q_u32(&mut a[..], 0, vld1q_u32(&h[..], 4));
    let mut v: Vec<u32, Gpa> = Vec::new_in(gpa);
    for i in 0..4 {
        v.push(10 * (i as u32 + 1));
    }
    by_vec(&mut v);
    bump(&mut v[..], 2);
    bump(&mut v[0..2], 0);
    println("{} {} {} {} {} {} {} {}", h[0], h[3], h[4], a[3], a[2], v[0], v[1], v[2]);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
2 5 2 5 3 11 22 31
