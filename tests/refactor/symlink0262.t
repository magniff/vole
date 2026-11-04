## 0.26.2: an edit of a module reached through a symlink (lib.vl ->
## shared/lib.vl) writes the file the link names and keeps the link:
## edit, fix, fmt and undo.
% test -L lib.vl && echo link
link
$ edit patch lib.vl:2 --old 'n * 2' --new 'n + n'
patched crate::lib::twice	lib.vl	+1 -1 lines
% test -L lib.vl && echo link kept; cat shared/lib.vl
link kept
pub fn twice(n: i64) -> i64 {
    let m = n + n;
    m
}

pub fn show(n: i64) {
    println(f"n = {n}");
}
$ fix --only fstring
fixed 1 f-string or format literal	lib.vl	+1 -1 lines
% test -L lib.vl && echo link kept; cat shared/lib.vl
link kept
pub fn twice(n: i64) -> i64 {
    let m = n + n;
    m
}

pub fn show(n: i64) {
    println("n = {n}");
}
$ undo
undid fixed 1 f-string or format literal	lib.vl	+1 -1 lines
% test -L lib.vl && echo link kept; cat shared/lib.vl
link kept
pub fn twice(n: i64) -> i64 {
    let m = n + n;
    m
}

pub fn show(n: i64) {
    println(f"n = {n}");
}
$ check
lib.vl:7:13: error[syntax.fstring] f-strings are removed (0.26.3): a format string takes the values as arguments | help: a name stays in its hole and an expression goes after the literal: `println("{n} {}", v.len())`; elsewhere `format_args("..", args)` | try: volec fix --only fstring --keep-braces main.vl
[exit 1]
% printf 'pub fn three()->i64{3}\n' >> shared/lib.vl
$ fmt lib.vl
formatted	lib.vl	+2 -1 lines
% test -L lib.vl && echo link kept; tail -3 shared/lib.vl
link kept
}

pub fn three() -> i64 { 3 }
