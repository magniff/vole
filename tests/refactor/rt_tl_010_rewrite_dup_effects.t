## XFAIL: RT-TL-10: rewrite copies a hole's expression into two places, running its side effects twice (open)
## `twice($a)` -> `thrice($a) - $a` at `twice(side(&mut c))`: the
## replacement names $a twice, and $a matched a call that changes c.
## It must be refused at that site (or bind it once: `{ let a = ..; .. }`),
## as `refactor signature --reorder` warns `refactor.effects`; today it
## writes `thrice(side(&mut c)) - side(&mut c)`, which checks and prints
## `1 2` instead of `2 1`.
$ run
2 1
$ rewrite 'twice($a)' 'thrice($a) - $a'
error rewrite.effects: main.vl:16:13: the replacement uses $a twice and it matched `side(&mut c)`, which has effects; nothing written
[exit 1]
$ run
2 1
