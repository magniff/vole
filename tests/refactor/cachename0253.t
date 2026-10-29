## (0.25.3) The tools' cache is the compiler's as it was run: the errors
## it keeps have `try:` lines that name it. Made by a check run by another
## name (./other-volec, the same file), it was read by `check`, which
## printed `try: ./other-volec ...`, and by an edit, whose own check's
## errors then differed from the cached ones by that name: new errors, and
## the edit refused itself (edit.breaks), though it fixes one error and
## leaves the other. (VOLE_CACHE_TRACE: the cache written before the
## command ends, not by its forked writer.)
% ln -s "$COMPILER" other-volec
% VOLE_CACHE_TRACE=/dev/null ./other-volec check
main.vl:4:5: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: ./other-volec fix --suggested main.vl
main.vl:10:9: error[type error] cannot assign to immutable variable 'count' | help: make it mutable: `var count`
[exit 1]
$ check
main.vl:4:5: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
main.vl:10:9: error[type error] cannot assign to immutable variable 'count' | help: make it mutable: `var count`
[exit 1]
$ edit patch count_to --old 'let count' --new 'var count'
patched crate::count_to	main.vl	+1 -1 lines
$ check
main.vl:4:5: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
[exit 1]
