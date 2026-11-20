#!/bin/sh
# XFAIL: RT-281: a value of an `impl Trait` type used after a move gets the try `.clone()`, which does not compile: its bounds do not say Clone (0.30.2)
# rustc: E0382 at each second use, and no clone help (an `impl Fn` or an
# `impl FnOnce` is Clone only when a bound says so). borrowck's
# clone_offered asks Clone of `undistinct(type)`, the hidden closure (a
# closure that captures nothing is Clone), not of the opaque type; so
# `volec check` offers `let q = p.clone();` and `g.clone()()`, and `fix
# --suggested` would write them. The case wants both moves reported and
# no `.clone()` offered. v0.30.1 and release-0.30.2 offer `let q =
# p.clone();` and do not report g's second call (RT-213, fixed on
# g302copy, which then offers `g.clone()()` too). From g302copy's report.
set -u
VOLEC=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat >"$T/main.vl" <<'VL'
fn plain(n: i64) -> impl Fn() -> i64 {
    move || n
}

fn once() -> impl FnOnce() -> i64 {
    || 5
}

fn main() {
    let p = plain(3);
    let q = p;
    let g = once();
    let a = g();
    println("{} {} {}", p(), q(), a + g());
}
VL
out=$(cd "$T" && VOLE_CACHE=off "$VOLEC" check main.vl 2>&1)
moved=$(echo "$out" | grep -c 'error\[borrowck.use_moved\]')
if [ "$moved" -ne 2 ]; then
    echo "FAIL: want 2 use_moved errors (p at line 14, g at line 14), got $moved: $(echo "$out" | head -3)"
    exit 1
fi
if echo "$out" | grep -q 'clone()'; then
    echo "FAIL: a .clone() offered for a value whose type is not Clone: $(echo "$out" | grep -o "try:.*clone()[^|]*" | head -2)"
    exit 1
fi
fix=$(cd "$T" && VOLE_CACHE=off "$VOLEC" fix --suggested --dry-run main.vl 2>&1)
if echo "$fix" | grep -q 'clone()'; then
    echo "FAIL: fix --suggested would write a .clone(): $(echo "$fix" | grep 'clone()' | head -2)"
    exit 1
fi
echo ok
