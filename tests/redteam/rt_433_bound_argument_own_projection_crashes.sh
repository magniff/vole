#!/bin/sh
# RT-433, fixed in 0.30.2 (obligations M2, the review's fixes: a projection past the depth limit is trait.overflow, E0275, not a crash; rustc says E0391).
# From the paused g302tparam work (its preexisting/pe6_a08). Since
# v0.30.1 at least (the same crash). RT-272's form, where another bound
# declares Out, passes. The supertrait form is rt_433b. It passes when
# check ends within 30 s with an error and exit 1, not a signal.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
use std::mem::size_of;

trait Tr<U> {
    type Out;
}

impl Tr<i64> for u8 {
    type Out = i64;
}

fn mid<T: Tr<T::Out>>(t: T) -> usize {
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
