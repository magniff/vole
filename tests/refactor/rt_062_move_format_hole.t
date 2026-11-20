## XFAIL: RT-62: refactor move does not see the names in a moved function's format holes: `{K}` takes the destination's K (0.30.2)
## a::show prints `a {K}`, a::K = 7. `refactor move crate::a::show --to
## crate` moves it beside crate::K = 1: the hole now names crate::K and
## the program checks and prints `a 1` instead of `a 7`. Written as
## `println("a {}", K)`, the same move is refused (refactor.collision:
## 'K' is already a name in crate), so the move's name check reads the
## code's names and not the holes'. It must refuse, or write the hole as
## an argument with the qualified path (`{}`, crate::a::K).
$ run
a 7
1
$ refactor move crate::a::show --to crate
error refactor.collision: 'K' is already a name in crate (const crate::K); nothing written
[exit 1]
$ run
a 7
1
