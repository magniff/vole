## XFAIL: T-SIG: a #[test] killed by SIGSEGV is counted as passed, and one that calls exit(3) is reported as exit 101 (open)
## T-SIG (the fifth review of f301e18, recorded in 0.30.1, not fixed
## there; on every build, the release's too): t_segv raises SIGSEGV
## and its process dies of it (the test build, `--vole-test t_segv`,
## exits 139), yet `volec test` counts it among the passed; t_exit3 calls
## C's exit(3) and the test build exits 101 (std::test's harness), not 3
## (rustc's harness exits 3). Both must fail, with the signal and the
## code the process ended with.
$ test
test main.vl: 1 passed, 2 failed (3 #[test]; -O0 and -O2 agree)
FAIL t_segv: stopped by signal 11 (SIGSEGV: an invalid memory access)
FAIL t_exit3: exit 3
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
