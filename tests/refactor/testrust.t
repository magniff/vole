## (0.27.1) The rust edition's contracts tested as properties: a `&T` or
## `&mut T` parameter is lent a generated T (`let k_owned = ..; let k =
## &k_owned;`), and a failure shows the value it was lent.
$ test --timeout 5
test main.vl: 1 passed, 1 failed (2 contracts; -O0 and -O2 agree)
FAIL total (contract, case 5 of 100, shrunk in 6 steps): main.vl:6:5: ensures failed: 'result >= *k' of 'total': result = -2, *k = 0
  trace: main.vl:6 total
  input: k = 0
  input: v = [-2]
  try: volec test total --seed 0x2dcede7d543a4ffd main.vl
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
[exit 1]
