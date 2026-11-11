## (0.28.0) `check` reads the program the same way with the tools' cache
## off and on (this transcript runs in both modes): it read only the std
## defaults and integer methods the source names when the cache was off,
## so `collect` had no `collect_in` to be answered with (alloc.no_in) and
## a misspelt `pow` had no nearest name. A build names `collect_in` too.
$ check
main.vl:2:5: error[type error] no method 'pw' on type 'i64' | help: did you mean 'pow'? | try: volec fix --suggested main.vl
main.vl:6:28: error[alloc.no_in] 'collect' allocates from nothing: pass the allocator, last, to 'collect_in' | help: this function's `gpa` is the allocator to pass | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
[exit 1]
% "$COMPILER" main.vl -o prog 2>&1 | grep -c 'alloc.no_in'
1
