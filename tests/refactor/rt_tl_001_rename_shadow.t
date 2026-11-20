## XFAIL: RT-TL-1: refactor rename of a function to the name of a local in scope at a call silently rebinds the call (open)
## main calls f(2) inside the scope of a closure `let g = |x| x * 100`.
## Renaming crate::f to g must be refused (the local g shadows it at that
## call), as renaming a local into a function's name already is; today it
## writes g(2), which checks and calls the closure: 200 instead of 3.
$ refactor rename f g
error refactor.collision: 'g' is already a name in the scope of a use of crate::f (local g at main.vl:30:9); nothing written
[exit 1]
$ run
3 100 8
1 2
7
