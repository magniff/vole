## XFAIL: RT-70: volec check never ends on a method call whose candidate is a by-value method of a trait for &S, called through &mut s (0.30.2)
## From the red team (R302B-16). rustc's probe reaches &S's impl at the
## deref step and the program prints `2 0`; volec check runs forever, its
## memory growing about 12 MB a second (0.28.0 to 0.30.0: SIGSEGV). Also
## `(&&s).m()` with `self` methods for &S and &&S. It must answer within
## 5 s of CPU, here with no error.
% (ulimit -t 5; volec check main.vl) 2>&1 | sed 's/^.*Cputime limit exceeded.*$/killed/'
ok: 0 errors in main.vl (1 file, 0 shaders)
