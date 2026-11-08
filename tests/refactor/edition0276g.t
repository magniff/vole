## fix --edition rust (0.27.7): flip28's T2, out_view_tie. A pointer to
## views a function takes as an out parameter and sets to a part of a
## view it takes (or a local each of whose values is one) is tied to it
## with the function's `'a`; the caller's `&m` of a `var` given to it is
## `&mut m` (rustc coerces a `&T` only to a `*const T`). Written, then
## built and run in the rust edition with the MVS program's output (the
## rust check's borrowck.outlives without the tie); the rustc twin agrees
## (rust_t_out_view).
$ main.vl -o mvs
ok: built mvs
% ./mvs
7 9
$ fix --edition rust --list-left main.vl
fixed, 10 views to &[T], 3 vars to 'let mut', 7 '.len's to '.len()', 1 integer annotated, 5 text literals to bytes, 1 type, 6 indexes cast to usize	main.vl	+14 -13 lines
$ fmt main.vl
note fmt.none: 1 file formatted already
% cat main.vl
// fix --edition rust (0.27.6): a pointer to views a function takes as an
// out parameter and sets to a part of a view it takes (`*message =
// line[m..n]`, or a local each of whose values is one) is tied to it, `fn f<'a>(line: &'a [u8], .., message:
// *mut &'a [u8])`: elided, the pointer's views would be of a region of
// their own, which the part of `line` does not outlive.
fn error_offset<'a>(line: &'a [u8], path: &[u8], message: *mut &'a [u8]) -> i64 {
    let mut colon: i64 = 0;
    while colon < line.len() as i64 && line[colon as usize] != b':' {
        colon += 1;
    }
    if colon == 0 || colon >= line.len() as i64 || &line[0..colon as usize] != path {
        return -1;
    }
    // UNSAFE: an out parameter, as the compiler's own.
    // SAFETY: message points to a live view (main's `m`).
    let mut text = if colon + 2 <= line.len() as i64 { &line[(colon + 2) as usize..line.len()] }
        else { &line[colon as usize..line.len()] };
    for q in 0..text.len() as i64 {
        if text[q as usize] == b'|' {
            text = &text[0..q as usize];
            break;
        }
    }
    unsafe {
        *message = text;
    }
    colon
}

fn main() {
    let mut m: &[u8] = b"";
    let line: &[u8] = b"main.vl: it fails | help";
    let at = error_offset(line, b"main.vl", &mut m);
    println("{} {}", at, m.len());
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
7 9
