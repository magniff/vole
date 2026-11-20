## XFAIL: RT-TL-19: refactor fold removes the calls of a predicate that has effects of its own (open)
## enabled(x) prints "checking {x}" and returns true. `fold enabled --as
## true` keeps the call whose argument calls side() (warning
## refactor.fold: "its arguments call functions, which the constant would
## not"), but folds `enabled(2) && c > 0` to `c > 0`, dropping the call
## and its io: "checking 2" is no longer printed. The function's own
## effects (query effects: io static panic) must count as the arguments' do: the call
## kept, or the fold refused.
$ query effects enabled
crate::enabled	io static panic
$ refactor fold enabled --as true
warning refactor.fold: 2 calls of crate::enabled are left: crate::enabled has effects (io static panic), which the constant would not; first: main.vl:13:8
$ run
checking 1
on
checking 2
1 true
