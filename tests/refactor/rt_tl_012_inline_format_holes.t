## XFAIL: RT-TL-12: refactor inline misses the callee's parameter uses in format holes (open)
## The known gap of signature --rename-param and extract-function (a
## parameter named in a format hole, `{x}`, is not a use to them), in a
## third tool: show(x) prints "x={x} {x:>3}"; inlining it at show(y) and
## show(3) must bind or substitute x in the holes too. Today the edit is
## refused with errors it made: `undefined variable 'x'` at the holes,
## and `no method 'fmt' on type '!'`.
$ refactor inline show
inlined crate::show at 2 calls, deleted it	main.vl	+8 -9 lines
$ run
x=7   7
x=3   3
7 3
