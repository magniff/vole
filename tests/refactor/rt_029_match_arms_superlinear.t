## XFAIL: RT-29: checking a match costs about the cube of its arms: a 2000-arm match of integers takes ~30 s to check (open)
## main.vl: `match x { 0 => 0, 1 => 2, ..., 1999 => 3998, _ => -1 }`.
## rustc checks it in milliseconds. The check phase costs 7x the
## instructions for twice the arms (500: 3.6 G, 1000: 25.4 G on 0.30.1):
## front/patterns/usefulness.vl check_arms rebuilds the matrix for every
## arm and runs `useful` over all the rows above it. It must end within
## 5 s of CPU.
% (ulimit -t 5; volec check main.vl) 2>&1 | sed 's/^.*Cputime limit exceeded.*$/killed/'
ok: 0 errors in main.vl (1 file, 0 shaders)
