## XFAIL: RT-15: volec rewrite drops the comments inside a site it rewrites (open)
## RT-15 (red team 1): a site of `add($a, $b)` laid out over several lines,
## a comment after each argument. The rewrite keeps the holes' code and
## loses both comments: the file is `let w = (x + x);`. Rewriting must not
## lose text; the comments are kept wherever the layout puts them, so the
## check is that both are still in the file.
$ rewrite 'add($a, $b)' '($a + $b)'
rewrote 1 site in 1 file	main.vl	+1 -4 lines
% grep -o 'the first\|the second' main.vl
the first
the second
% volec run
6
