## volec fix --only std015 on a program written against 0.14's std
## (tests/refactor/std015run/, whose output under 0.14 is below): with
## 0.15's std it does not compile, migrated it prints what it printed
## under 0.14 (the design's acceptance: the migration is exact); a second
## run finds nothing to do. (0.26.3: the program writes its allocator, as
## 0.16's `fix --only alloc016` did; that fix is gone with std's ambient
## functions.)
$ fix --only std015
fixed 4 calls of 0.14's std	main.vl	+4 -4 lines
$ fix --only conventions
fixed 1 '&mut e' to '&e', 4 'let mut's / 'mut x's to var	main.vl	+5 -5 lines
% "$COMPILER" main.vl -o prog && ./prog < input.txt
a 42
b -1
c 7
empty 1
total 10
count 4
more 0
ok: built prog
$ fix --only std015
note fix.none: nothing to fix
