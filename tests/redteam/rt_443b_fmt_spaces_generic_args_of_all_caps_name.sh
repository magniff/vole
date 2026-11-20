#!/bin/sh
# XFAIL: RT-443b: (RT-443's mechanism; its trigger is a type name of two or more characters with no lowercase letter, a constant's shape, not a final digit) `volec fmt` writes `-> UL<'x> {` as `-> UL < 'x > {` and `SL<'x>` as `SL < 'x >` (0.30.2)
# rustfmt keeps `UL<'x>`. From the g302static work (its pre/pre02).
# Since v0.30.1 at least (the same output). Measured on the release
# build: AB, A1, A_B, XY_1, HTTP, UL, SL, W3 are spaced; W, Wx, Ab2,
# W2b, ABc, Http are kept. Layout only: the program checks the same
# after. It passes when fmt keeps `UL<'x>` and `SL<'x>`.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
union UL<'x> {
    a: &'x u64,
    b: usize,
}

struct SL<'x> {
    a: &'x u64,
}

fn mk<'x>(x: &'x u64) -> UL<'x> {
    UL { a: x }
}

fn mks<'x>(x: &'x u64) -> SL<'x> {
    SL { a: x }
}

fn main() {}
VL
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 30; exec @ARGV' "$V" fmt main.vl > out.txt 2>&1
bad=$(grep -n -E '(UL|SL) <' main.vl)
[ -n "$bad" ] && { echo "fmt wrote: $bad"; exit 1; }
grep -q "fn mk<'x>(x: &'x u64) -> UL<'x> {" main.vl || { echo "fmt lost the fn line: $(cat out.txt)"; exit 1; }
exit 0
