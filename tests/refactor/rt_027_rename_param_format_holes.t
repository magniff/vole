## XFAIL: RT-27: refactor signature --rename-param leaves the parameter's uses in format-string holes (open)
## RT-27 (red team 1): `{count}` and `{count:>5}` in a format string are
## uses of the parameter (refactor rename renames such holes for a const
## or a static). --rename-param renames the parameter and the plain use
## and leaves both holes, so the file no longer checks ("undefined
## variable 'count'"), and without --no-check it refuses with "the uses of
## crate::total no longer fit its new shape". The renamed program must
## build and print what it printed.
$ refactor signature total --rename-param count n
renamed parameter count to n of crate::total	main.vl	+3 -3 lines
% grep -c '{n}' main.vl
1
% volec run
count=3 doubled=6     3 3
6
