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
ok: 0 errors in main.vl
% printf 'pub fn three()->i64{3}\n' >> shared/lib.vl
$ fmt lib.vl
formatted	lib.vl	+2 -1 lines
% test -L lib.vl && echo link kept; tail -3 shared/lib.vl
link kept
}

pub fn three() -> i64 { 3 }
