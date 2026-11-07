## fix --edition rust (0.27.4, gate 3): a row whose receiver is a row's
## call starting at the same place (`v.as_mut_slice().sort()`: each is
## put once by both its ends), an array element's address cast to
## another pointee (`&raw const w[0]`, past the parenthesis), and
## std::str's memchr as an iterator's position (std2 has none; its use
## goes). Written, then built and run in the rust edition with the MVS
## program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
1 3 2 99
$ fix --edition rust --list-left main.vl
fixed, 1 view to &[T], 1 '&x' to '&mut x', 1 var to 'let mut', 1 integer annotated, 1 import, 2 text literals to bytes, 1 type, 3 std calls by rewrite.tsv	main.vl	+8 -7 lines
% cat main.vl
// fix --edition rust (0.27.4, gate 3): a row on a receiver that is
// itself a row's call (`v.as_mut_slice().sort()`, both starting at `v`),
// `(&w[0]) as *u8` of an array, and std::str's memchr, which std2 has
// not: an iterator's position, its use dropped.


fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(3);
    v.push(1);
    v.as_mut_slice().sort_unstable();
    let w: [i64; 1] = [258i64];
    // UNSAFE: a test. SAFETY: w is 8 bytes, its first one read.
    let b = unsafe { *((&raw const w[0]) as *mut u8) };
    let text: &[u8] = b"abc";
    let k = match text.iter().position(|c| *c == b'c').map(|i| i as i64) { Some(i) => i, None => -1 };
    println("{} {} {} {}", v[0], v[1], b, k + text[0] as i64);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
1 3 2 99
