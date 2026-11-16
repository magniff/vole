## XFAIL: RT-TL-21: fix --suggested applies i64/u64/usize to f64 casts, which round (open)
## guide tools: "A fix that would change what the code means (a lossy
## conversion ...) is not made"; `d as f32` (f64 to f32) is refused,
## "f64 to f32 rounds". But `big as f64` of an i64 (and u64, usize) is
## applied: 9007199254740993 becomes 9007199254740992, u64::MAX
## 18446744073709552000. These must be refused the same way.
$ fix --suggested
main.vl:14:35: error[type error] expected 'f64', got 'i64' | help: only widening is implicit: convert explicitly | try: big as f64
main.vl:14:48: error[type error] expected 'f64', got 'u64' | help: only widening is implicit: convert explicitly | try: u as f64
main.vl:14:62: error[type error] expected 'f64', got 'usize' | help: only widening is implicit: convert explicitly | try: n as f64
note fix.refused: main.vl:14:35: not applied: `big as f64`: i64 to f64 rounds
note fix.refused: main.vl:14:48: not applied: `u as f64`: u64 to f64 rounds
note fix.refused: main.vl:14:62: not applied: `n as f64`: usize to f64 rounds
note fix.none: nothing to fix
[exit 1]
% git diff --stat
