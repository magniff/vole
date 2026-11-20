#!/bin/sh
# XFAIL: RT-306: after a type error in a `scan` closure leaves B unknown, the check of `println("{:?}", g)` reports three errors inside std: "<std>: unknown type 'B'", "undefined variable 'N'", "cannot infer type parameter 'T' of '[T; N]::fmt'" (0.30.2)
# rustc reports the one error, E0308/E0277 at line 4 (`*st += *x`, i32 +=
# i64). An error type must not instantiate std's code: every error is at
# the program's lines. v0.28.0 to v0.30.1 the same.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
fn main() {
    let v = [1i64, 2, 3];
    let g = v.iter().scan(0i32, |st, x| {
        *st += *x;
        Some(*st)
    }).last();
    let h = v.iter().scan(0i32, |st, x| {
        *st += *x;
        Some(*st)
    }).max();
    println("{:?} {:?}", g, h);
}
VL
out=$(cd "$w" && VOLE_CACHE=off "$V" check main.vl 2>&1)
st=0
if ! printf '%s\n' "$out" | grep -q '^main.vl:4:'; then
    echo "FAIL: no error at line 4 (the i32 += i64)"
    st=1
fi
if printf '%s\n' "$out" | grep -q '^<std>'; then
    echo "FAIL: errors reported inside std:"
    printf '%s\n' "$out" | grep '^<std>' | cut -c1-160
    st=1
fi
[ $st -eq 0 ] && echo ok
exit $st
