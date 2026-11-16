## XFAIL: RT-67: refactor extract-function moves the drop of a value the lines declare and do not give back to the end of the new function (0.30.2)
## e (a D, with a Drop impl that prints) is declared in lines 13-14 and
## not used after them, so it lives to the end of main: `a 2`, `b`,
## `end 1`, `drop 2`, `drop 1`. Extracted into nf(), e is dropped when
## nf returns: the program checks and prints `a 2`, `drop 2`, `b`, ...
## The lines' values with drop glue must be given back (and dropped where
## they were) or the extraction refused.
$ run
a 2
b
end 1
drop 2
drop 1
$ refactor extract-function main --lines 13-14 --to nf
error refactor.drop: lines 13-14 declare e (D, Drop), which lives to the end of crate::main; NEW would drop it when it returns; nothing written
[exit 1]
$ run
a 2
b
end 1
drop 2
drop 1
