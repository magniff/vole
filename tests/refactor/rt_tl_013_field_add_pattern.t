## XFAIL: RT-TL-13: refactor field --add leaves exhaustive struct patterns as they were, and its try: names the same command (open)
## `let P { a, b } = p;` in sum. Adding a field must extend that pattern
## (`P { a, b, .. }` or `c: _`) as it fills in the literals; today the
## edit is refused, `the pattern of 'P' does not mention field 'c'`, and
## the `try:` it prints is the refactoring that was just run (a loop).
$ refactor field P --add 'c: i64 = 100'
added field c: i64 to crate::P, 3 literals	main.vl	+5 -4 lines
$ run
3 7 12
1 4 0
3
false
