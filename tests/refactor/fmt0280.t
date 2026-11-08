## (0.28.0) fmt reads a file in its program's edition: words.vl has no
## `// EDITION: rust` line of its own, main.vl, its root, has (0.27.7
## read words.vl as MVS: `'static` an unterminated character literal).
## By the file's path (the nearest main.vl at or above it) and in the
## loaded program.
$ fmt --check words.vl
words.vl
error fmt.unformatted: 1 of 1 file is not formatted
try: volec fmt --dry-run words.vl
try: volec fmt words.vl
[exit 1]
$ fmt --check
words.vl
error fmt.unformatted: 1 of 2 files are not formatted
try: volec fmt --dry-run words.vl
try: volec fmt words.vl
[exit 1]
$ fmt words.vl
formatted	words.vl	+1 -1 lines
% cat words.vl
// A module of a rust-edition program: no edition line of its own.
pub fn first(text: &'static [u8]) -> &'static [u8] {
    let mut i: usize = 0;
    while i < text.len() && text[i] != b' ' {
        i += 1;
    }
    &text[0..i]
}
$ fmt --check words.vl main.vl
$ check main.vl
ok: 0 errors in main.vl
