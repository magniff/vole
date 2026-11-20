## XFAIL: RT-TL-11: refactor inline of a function of another module leaves its names unqualified, so they resolve in the caller's module (open)
## m::k(x) is `x + h()`, h being m's private h (1000); main.vl has its
## own h (1). Inlining m::k into main must call m::h (it may make it
## pub, as it does, and write `crate::m::h()`); today it writes
## `3 + h()`, which checks and calls crate::h: `3 4`, not `3 1003`.
$ run
3 1003
$ refactor inline m::k
inlined crate::m::k at 1 call, deleted it	2 files	+2 -6 lines
$ run
3 1003
