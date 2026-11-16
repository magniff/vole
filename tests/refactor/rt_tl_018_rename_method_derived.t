## XFAIL: RT-TL-18: refactor rename of a method to the name of a derived trait's method makes that trait's calls call it (open)
## S derives Clone; main calls s.clone() (the derived one) and s.dup().
## Renaming S::dup to clone must be refused (an inherent method shadows
## the trait's at every `x.clone()` of an S), as it is for the program's
## own trait methods (`'n' is already a name in crate (method <crate::S
## as Tr>::n)`). Today it writes `fn clone`, which checks, and `a` changes
## from S { v: 1 } to S { v: 101 }.
$ refactor rename S::dup clone
error refactor.collision: 'clone' is already a name in crate (method <crate::S as Clone>::clone); nothing written
try: volec query def '<crate::S as Clone>::clone'
[exit 1]
$ run
S { v: 1 } S { v: 101 } 3
