## (0.25.5) A bare `volec` in a `%` line is the compiler under test (first
## in PATH), not whatever is installed (mod254 #13): the same file as the
## one `$` lines run.
% cmp "$(command -v volec)" "$COMPILER" && echo the compiler under test
the compiler under test
