## 0.30: `volec check` folds an error repeated at six sites or more
## (the same code and message) into one line, its first site's, with
## the sites and files counted; fewer repeats (`other_name`, twice) are
## as before. (0.29: 50 lines of one missing import, 230 characters
## each, hid the 20 real errors behind the limit.)
$ check
main.vl:4:19: error[type error] undefined variable 'limit' (7 sites in 2 files, the first here; --each lists them)
main.vl:8:18: error[type error] expected 'i32', got 'i64' | help: only widening is implicit: convert explicitly | try: 1i64 as i32
main.vl:9:13: error[type error] undefined variable 'other_name'
main.vl:10:13: error[type error] undefined variable 'other_name'
[exit 1]
## --each: every site its own line.
$ check --each
main.vl:4:19: error[type error] undefined variable 'limit'
main.vl:5:19: error[type error] undefined variable 'limit'
main.vl:6:19: error[type error] undefined variable 'limit'
main.vl:7:19: error[type error] undefined variable 'limit'
main.vl:8:18: error[type error] expected 'i32', got 'i64' | help: only widening is implicit: convert explicitly | try: 1i64 as i32
main.vl:9:13: error[type error] undefined variable 'other_name'
main.vl:10:13: error[type error] undefined variable 'other_name'
calc.vl:3:10: error[type error] undefined variable 'limit'
calc.vl:4:10: error[type error] undefined variable 'limit'
calc.vl:5:10: error[type error] undefined variable 'limit'
[exit 1]
## A check that names its form lists every site: the tools' own runs
## (an edit's check), the hooks (--json) and the tests read it.
$ check --diagnostics=short 2>&1 | grep -c 'undefined variable .limit'
7
$ check --json 2>&1 | grep -c 'undefined variable .limit'
7
