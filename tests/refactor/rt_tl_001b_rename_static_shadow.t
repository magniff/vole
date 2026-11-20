## XFAIL: RT-TL-1: refactor rename of a function to the name of a local in scope at a call silently rebinds the call (open)
## The same for a static: f has `let y = 5;` then reads `K + y + S`.
## Renaming crate::S to y must be refused (the local y shadows it at
## that use); today it writes `K + y + y`, which checks: 110, not 1105.
$ refactor rename S y
error refactor.collision: 'y' is already a name in the scope of a use of crate::S (local y at main.vl:6:9); nothing written
[exit 1]
$ run
1105
