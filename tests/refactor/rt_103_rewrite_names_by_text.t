## XFAIL: RT-103: rewrite matches a pattern's names and writes a replacement's names by their text: another module's function of the same name is rewritten, and a local closure captures the replacement's call (0.30.2)
## crate::old and crate::new compute the same (x + 1); the rewrite
## `old($a)` -> `new($a)` is meant to keep the meaning. It also rewrites
## a.vl's `old(5)`, a call of a::old (x * 1000), into a::new (x - 1), and
## main's `old(2)`, after `let new = |x: i64| x * 100;`, into a call of the
## closure. It answers `rewrote 3 sites in 2 files` and the program checks
## and prints `2`, `200 300`, `4` for `2`, `3 300`, `5000`. The pattern's
## `old` must match calls of what `old` is where the rewrite is asked
## (crate::old, also when written crate::old), and the replacement's `new`
## must be written so that it names crate::new at each site (qualified),
## or the site refused.
$ run
2
3 300
5000
$ rewrite 'old($a)' 'new($a)'
rewrote 2 sites in 1 file	main.vl	+2 -2 lines
$ run
2
3 300
5000
