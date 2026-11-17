## XFAIL: RT-TL-13: refactor field --add leaves exhaustive struct patterns as they were, and its try: names the same command (open)
## The same for a field's rename: `let P { a, .. } = p;` and `let P { a: x,
## b } = mk(5);` must become `P { z: a, .. }` and `P { z: x, b }` (the
## literals' shorthand `P { a, b: 2 }` is already made `P { z: a, b: 2 }`).
## Today both rename P.a z and refactor field --rename refuse with
## `no field 'a' in struct 'P'` at the patterns, and the try: is
## `refactor field crate::P --rename a z`, which fails the same way.
$ refactor rename P.a z
renamed crate::P.a to z	main.vl	+6 -6 lines
$ run
1 5 2 9 P { z: 1, b: 2 } P { z: 3, b: 2 }
