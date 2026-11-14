## 0.30: fix reads every error. The check stopped at 50, so a fix run
## answered 50 errors and its four rounds 200 more: a program with 260
## missing imports was refused (`fix --only imports`: the check of the
## edit met errors past the old limit as new ones) or left half done
## (`fix --suggested`), and 1158 of them took about 15 runs in 0.29.
$ check --diagnostics=short 2>&1 | tail -1
error: too many errors; stopping after 50 (--max-errors=N: more, 0: all)
$ fix --only imports
fixed 260 missing imports	main.vl	+19 -0 lines
$ check
ok: 0 errors in main.vl (2 files, 0 shaders)
% git checkout -q .
$ fix --suggested
fixed 260 missing imports	main.vl	+19 -0 lines
$ check
ok: 0 errors in main.vl (2 files, 0 shaders)
% git checkout -q .
