## XFAIL: RT-68: edit wrap --in unsafe --lines puts the lines' lets in a new block: a value with a Drop impl is dropped at its end (0.30.2)
## e (a D, whose Drop impl prints) is declared on line 13 and lives to
## the end of main: `a 2`, `b`, `end 1`, `drop 2`, `drop 1`. `edit wrap
## main --in unsafe --lines 13-14` writes `unsafe { let e = ..; println(..); }`:
## e is dropped at the block's end, and the program checks and prints
## `a 2`, `drop 2`, `b`, ... A wrap must not end a let's scope: refuse
## lines that declare a value with drop glue (or one used after them),
## or wrap the expressions, not the lets.
$ run
a 2
b
end 1
drop 2
drop 1
$ edit wrap main --in unsafe --lines 13-14
error edit.drop: line 13 declares e (D, Drop), which the block would drop at its end, before the end of crate::main; nothing written
[exit 1]
$ run
a 2
b
end 1
drop 2
drop 1
