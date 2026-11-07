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
