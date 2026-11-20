## XFAIL: RT-TL-1: refactor rename of a function to the name of a local in scope at a call silently rebinds the call (open)
## The same capture by the prelude: main calls the prelude's drop(b).
## Renaming crate::consume to drop must be refused (crate::drop would
## shadow the prelude's at that call); today it writes `fn drop`, which
## checks, and drop(b) now runs consume's body: "consumed 1" twice.
$ refactor rename consume drop
error refactor.collision: 'drop' is already a name in the prelude, used in crate::main (main.vl:10:5); nothing written
[exit 1]
$ run
consumed 1
end
