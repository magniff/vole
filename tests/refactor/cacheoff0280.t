## (0.28.0) `check` gives the same errors and helps with the tools' cache
## off and on (this transcript runs in both modes). With the cache off it
## reads std as a build does, only the defaults and integer methods the
## source names: `collect` had no `collect_in` to be answered with
## (alloc.no_in), and a misspelt `pow` had no nearest name. A default
## NAME_in now comes with NAME, and an unknown method of an integer is
## offered every integer method. A build names `collect_in` too.
$ check
main.vl:2:5: error[type error] no method 'pw' on type 'i64' | help: did you mean 'pow'? | try: volec fix --suggested main.vl
main.vl:6:28: error[alloc.no_in] 'collect' allocates from nothing: pass the allocator, last, to 'collect_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
[exit 1]
% "$COMPILER" main.vl -o prog 2>&1 | grep -c 'alloc.no_in'
1
