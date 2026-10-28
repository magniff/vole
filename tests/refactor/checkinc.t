## `volec check -I DIR` (0.25.2): `import "header.h"` looks in DIR first,
## as a build's -I does (-IDIR too); without it the header is not found.
$ check
main.vl:1:8: error[C import] header not found: widget.h
[exit 1]
$ check -I inc
ok: 0 errors in main.vl
$ check -Iinc
ok: 0 errors in main.vl
