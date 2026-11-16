## XFAIL: RT-TL-8: places builds the bodies of a chain of generic calls n*n/2 times (open)
## main.vl: f0<T> calls f1<T> ... calls f1000<T>, main calls f0(1i64).
## The program has 1000 instances (the object has 1004 functions), but
## `volec check --time-passes` reports `502582 bodies` in places (n=100:
## 5332, 200: 20582, 400: 81082) and 2.1 s of its 4.3 s there. The check
## must end within 2 s of CPU, with about n bodies.
% (ulimit -t 2; volec check main.vl) 2>&1 | sed 's/^.*Cputime limit exceeded.*$/killed/'
ok: 0 errors in main.vl (1 file, 0 shaders)
