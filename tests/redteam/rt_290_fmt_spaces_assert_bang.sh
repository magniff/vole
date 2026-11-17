#!/bin/sh
# XFAIL: RT-290: `volec fmt` writes `assert!(c, "m")` as `assert !(c, "m")`, a space rustfmt and the grammar's macro form do not have (0.30.2)
# fmt must keep `name!(` together for every macro-like form (assert!,
# assert_eq!, debug_assert!, panic!, vec!, ...). From g302probe; v0.30.1 the same.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/a.vl" <<'VL'
fn main() {
    let c = true;
    assert!(c, "m");
    assert_eq!(1, 1);
    debug_assert!(c);
    println("ok");
}
VL
VOLE_CACHE=off "$V" fmt "$w/a.vl" > /dev/null 2>&1
if grep -qE '[a-z_] !\(' "$w/a.vl"; then
    echo "FAIL: fmt split a macro name from its '!':"
    grep -nE '[a-z_] !\(' "$w/a.vl"
    exit 1
fi
echo ok
