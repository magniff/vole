#!/bin/sh
# XFAIL: RT-235c: (R302E-12's drop order, a deadlock) a match arm `Some(d) => *m.lock().unwrap() + d.k` drops d, whose Drop locks m, while the arm's MutexGuard temporary still holds m: the program never ends; rustc drops the guard first and prints `drop D` and `x 15 11` (0.30.2)
# R302E-12: an arm's expression temporaries are dropped after the arm's
# bindings (places/build.vl temp_home). A shell case because the built
# program does not end: it gets 20 s at -O0 and at -O2. Passes when both
# builds print rustc's two lines (twin: r302e_012c_match_arm_drop_order_deadlocks.rs.txt).
# Usage: r302e_012c_match_arm_drop_order_deadlocks.sh VOLEC
V=$1
case "$V" in /*) ;; *) V="$PWD/$V" ;; esac
w=$(mktemp -d "${TMPDIR:-/tmp}/r302e12c.XXXXXX")
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
use std::sync::Mutex;

struct D<'a> {
    m: &'a Mutex<i64>,
    k: i64,
}

impl<'a> Drop for D<'a> {
    fn drop(&mut self) {
        *self.m.lock().unwrap() += 1;
        println("drop D");
    }
}

fn pick<'a>(m: &'a Mutex<i64>) -> Option<D<'a>> {
    Some(D { m: m, k: 5 })
}

fn main() {
    let m = Mutex::new(10i64);
    let x = match pick(&m) {
        Some(d) => *m.lock().unwrap() + d.k,
        None => 0,
    };
    println("x {} {}", x, *m.lock().unwrap());
}
VL
printf 'drop D\nx 15 11\n' > "$w/want"
for o in 0 2; do
    if ! VOLE_CACHE=off "$V" -O$o "$w/main.vl" -o "$w/p$o" > "$w/build$o" 2>&1; then
        echo "FAIL: -O$o does not build:"; head -5 "$w/build$o"; exit 1
    fi
    perl -e 'alarm 20; exec @ARGV' "$w/p$o" > "$w/out$o" 2>&1
    rc=$?
    if [ $rc -ge 128 ]; then echo "FAIL: -O$o: the program did not end within 20 s (deadlock)"; exit 1; fi
    if ! cmp -s "$w/want" "$w/out$o"; then echo "FAIL: -O$o printed:"; cat "$w/out$o"; exit 1; fi
done
echo "ok: -O0 and -O2 print rustc's lines"
exit 0
