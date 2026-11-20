#!/bin/sh
# XFAIL: RT-433b: (RT-433's mechanism, through a supertrait) `fn mid<T: Sub<T::Out>>(t: T)` with `trait Sub<U>: Tr` and Tr declaring Out crashes the compiler (bus error, exit 138) in check and build; rustc E0391 (cycle detected when computing the bounds for type parameter `T`) (0.30.2)
# From the paused g302tparam work (its preexisting/pe6_a09). Since
# v0.30.1 at least (the same crash). It passes when check ends within
# 30 s with an error and exit 1, not a signal.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
use std::mem::size_of;

trait Tr {
    type Out;
}

trait Sub<U>: Tr {}

impl Tr for u8 {
    type Out = i64;
}

impl Sub<i64> for u8 {}

fn mid<T: Sub<T::Out>>(t: T) -> usize {
    size_of::<T::Out>()
}

fn main() {
    println("{}", mid(1u8));
}
VL
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 30; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
[ $rc -eq 1 ] || { echo "check exit $rc (138: bus error, 142: no end within 30 s)"; tail -3 out.txt; exit 1; }
grep -q 'error' out.txt || { echo "exit 1 with no error line"; exit 1; }
exit 0
