## XFAIL: RT-65: refactor signature --type x '&T' of a parameter whose type has a Drop impl moves the drop to the caller's scope end (0.30.2)
## f(d: D) takes the D and drops it when f returns, so `drop 1` prints
## before `after 1`. `refactor signature f --type d '&D'` writes
## `fn f(d: &D)` and `f(&d)`: d now lives to the end of main, and the
## program checks and prints `in f`, `after 1`, `drop 1`. A parameter
## whose type has drop glue that does something (a Drop impl) must not
## change from a move to a borrow without the drop kept where it was
## (`f(&d); drop(d);` at the call) or a refusal.
$ run
in f
drop 1
after 1
$ refactor signature f --type d '&D'
error refactor.drop: main.vl:18:15: d of type D (Drop) is moved into crate::f here, and borrowed it would be dropped at the end of crate::main; nothing written
[exit 1]
$ run
in f
drop 1
after 1
