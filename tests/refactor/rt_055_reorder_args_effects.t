## XFAIL: RT-55: refactor signature --reorder and --remove move or drop arguments whose effects are not calls, with no warning (0.30.2)
## `order({ d += 1; d }, { d += 2; d })`, `first(r, { d += 100; d })` and
## `div(arr[i], 10 / z)`: the arguments change d, or panic, without
## calling a function, so refactor.effects (which looks for calls) says
## nothing. --reorder b,a writes `order({ d += 2; d }, { d += 1; d })` and
## `div(10 / z, arr[i])`; --remove b writes `first(r)`: the program checks
## and prints `32 32 3` and panics with `attempt to divide by zero`
## instead of `13 13 103` and the index panic. The tool must keep the
## effects in their order (bind the arguments in a block, a removed one
## too) or refuse, for any argument with an effect: an assignment, a
## panic (index, division, overflow, unwrap), not only a call.
$ run
13 13 103
main.vl:23:17: index out of bounds: index 5, length 3
[exit 101]
$ refactor signature order --reorder b,a
error refactor.effects: main.vl:17:19: arguments with effects would be evaluated in another order; nothing written
[exit 1]
$ refactor signature first --remove b
error refactor.effects: main.vl:18:22: a removed argument has effects; nothing written
[exit 1]
$ refactor signature div --reorder b,a
error refactor.effects: main.vl:23:17: arguments with effects would be evaluated in another order; nothing written
[exit 1]
$ run
13 13 103
main.vl:23:17: index out of bounds: index 5, length 3
[exit 101]
