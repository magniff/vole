#!/bin/sh
# XFAIL: RT-330: an `ensures` reading a parameter the body moved reports "moved at" the function's start (3:1), not the move `take(s)` at 5:3 (0.30.2)
# The same use after a move in a body names the move's position. Seen on
# v0.30.1 and the release. From the second re-review of g302holes.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
struct N { v: i64 }
fn take(n: N) -> i64 { n.v }
fn f(s: N) -> i64
    ensures result > 0 && s.v > 0 && s.v < 10
{ take(s) }
fn main() { println("{}", f(N { v: 4 })); }
VL
out=$(cd "$w" && VOLE_CACHE=off "$V" check main.vl 2>&1)
if ! printf '%s\n' "$out" | grep -q 'use_moved'; then
    echo "FAIL: no use_moved error:"; printf '%s\n' "$out" | head -3 | cut -c1-160; exit 1
fi
if ! printf '%s\n' "$out" | grep 'use_moved' | grep -q 'moved at main.vl:5:'; then
    echo "FAIL: 'moved at' does not name the move at line 5:"
    printf '%s\n' "$out" | grep 'use_moved' | head -1 | cut -c1-200
    exit 1
fi
echo ok
