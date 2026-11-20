## XFAIL: RT-64: refactor field --remove drops the literals' initializers with their effects, with no warning (0.30.2)
## `S { a: bump(&mut d), b: 2 }` and `S { b: 3, a: { d += 10; d } }`:
## `refactor field S --remove a` writes `S { b: 2 }` and `S { b: 3 }`;
## the calls and the assignment are gone, and the program checks and
## prints `2 3 0` instead of `2 3 11`. The removal must keep an
## initializer with effects (as a statement before the literal, in its
## order) or refuse, as RT-55 asks of `signature --remove`.
$ run
2 3 11
$ refactor field S --remove a
error refactor.effects: main.vl:13:20: a removed field's value has effects; nothing written
[exit 1]
$ run
2 3 11
