## (0.25.2) A case stopped by --timeout having used under half of it in
## processor time was waiting, not running (a loaded machine, a stalled
## disk): it runs again, twice at most, and its last run is judged.
## `once` sleeps 5 s on its first run only (the file `stalled` marks it):
## its second run passes. `forever` sleeps on every run: it fails after
## three. A loop (testcmd.t's `hang`) is stopped once.
$ test --timeout 1
test main.vl: 1 passed, 1 failed (2 cases; -O0 and -O2 agree)
FAIL forever: no exit after 1 s (--timeout S): stopped by signal 14 (SIGALRM: a time limit)
  trace: main.vl:17 main
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
% cat stalled
x
