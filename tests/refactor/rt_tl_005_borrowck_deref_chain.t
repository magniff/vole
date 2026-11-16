## XFAIL: RT-TL-5: borrowck takes cubic time on a chain of dereferences (open)
## main.vl: a reference of 2000 `&` read back through 2000 `*` (4 KB).
## borrowck alone takes 0.33 s at 500, 2.3 s at 1000, 18.8 s at 2000
## (`volec check --time-passes`): about the cube of the chain. The check
## must end within 5 s of CPU (it should take milliseconds).
% (ulimit -t 5; volec check main.vl) 2>&1 | sed 's/^.*Killed.*$/killed/; s/^.*CPU time limit.*$/killed/'
ok: 0 errors in main.vl (1 file, 0 shaders)
