## (0.25.3) What a test printed: under its failure always (its own lines,
## not the runtime's report, which is the reason), and with
## --show-output (--nocapture) under its name. Passing tests and the flag
## off: the summary alone, as before.
$ test prints_ok quiet_ok hi
test main.vl: 3 passed (1 case, 2 #[test]; -O0 and -O2 agree)
$ test prints_ok quiet_ok hi --show-output
test main.vl: 3 passed (1 case, 2 #[test]; -O0 and -O2 agree)
OUTPUT hi
  stdout: hello
  stderr: warning: on stderr
OUTPUT prints_ok
  stdout: value is 42
  stderr: to stderr 7
OUTPUT quiet_ok: none
$ test
test main.vl: 4 passed, 4 failed (2 cases, 4 #[test], 2 #[property]; -O0 and -O2 agree)
FAIL bye: stdout differs at line 1 (1 line expected, 1 printed)
  - bye
  + hello
  stderr: warning: on stderr
FAIL prints_and_fails: main.vl:21:5: assertion failed: '1 + 1 == 3'
  trace: main.vl:21 prints_and_fails
  stdout: x = 3
  stderr: note from the test
FAIL errs: test returned Err("bad thing")
  stdout: before the Err
FAIL small (property, case 36 of 100, shrunk in 60 steps): main.vl:33:5: assertion failed: 'x < 200': x = 200
  trace: main.vl:33 small
  input: x = 200
  stdout: x=200
  try: volec test small --seed 0x7d6ce172e098998c main.vl
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
## a property's generated cases run quiet; the failing one, replayed,
## prints under its failure
$ test hi bye small fine --show-output -O2
test main.vl: 2 passed, 2 failed (2 cases, 2 #[property]; -O2 only)
FAIL bye: stdout differs at line 1 (1 line expected, 1 printed)
  - bye
  + hello
  stderr: warning: on stderr
FAIL small (property, case 36 of 100, shrunk in 60 steps): main.vl:33:5: assertion failed: 'x < 200': x = 200
  trace: main.vl:33 small
  input: x = 200
  stdout: x=200
  try: volec test small --seed 0x7d6ce172e098998c main.vl
OUTPUT hi
  stdout: hello
  stderr: warning: on stderr
OUTPUT fine: none (its generated cases run quiet; a failing one prints under its failure)
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
$ test prints_ok --nocapture -O2
test main.vl: 1 passed (1 #[test]; -O2 only)
OUTPUT prints_ok
  stdout: value is 42
  stderr: to stderr 7
