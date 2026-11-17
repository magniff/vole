## main.vl: one function of 3000 `let x = x + 1;` (57 KB). `volec check`:
## 1000 lets 0.74 s, 2000 8.9 s, 3000 20.1 s, 5000 more than 60 s, all
## in the `check` phase (--time-passes); distinct names (`let xI = I;`)
## 1000 0.2 s, 3000 3.9 s, 5000 17.3 s. It must end within 5 s of CPU.
% (ulimit -t 5; volec check main.vl) 2>&1 | sed 's/^.*Cputime limit exceeded.*$/killed/'
ok: 0 errors in main.vl (1 file, 0 shaders)
