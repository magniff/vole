## XFAIL: RT-48: refactor rename of a const to the name of a pattern binding makes the binding a const pattern (0.30.2)
## pick's `if let Some(found) = o` binds `found`. Renaming crate::LIMIT
## to found makes that pattern the const (Some(5) only) and the `found`
## in its body the const: the program checks, and pick(Some(3)) is -1
## instead of 3. The rename must be refused (a binding of that name is
## in a pattern where the new name would resolve to the const), as a
## local that shadows a renamed function must be (RT-TL-1).
$ refactor rename LIMIT found
error refactor.collision: 'found' is a binding in a pattern at main.vl:11:17, which would become the const crate::LIMIT; nothing written
[exit 1]
$ run
1 0 90
3 -1
