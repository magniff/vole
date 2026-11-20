#!/bin/sh
# XFAIL: RT-409b: (RT-409's family) `volec fmt` lays out a type's arguments that start with a qualified path, `Option< <T as Tr>::Out >` in a where clause, as `Option < <T as Tr>::Out >` (a space before the type's `<`) (0.30.2)
# rustfmt writes `Option<<T as Tr>::Out>`. From the paused g302tparam
# work (its preexisting/pe5). Since v0.30.1 at least (the same output).
# Layout only: the program checks the same before and after. It passes
# when fmt keeps no space between `Option` and its `<`.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
trait Tr {
    type Out;
}

impl Tr for u8 {
    type Out = i64;
}

fn f<T>(t: T) -> usize
where
    T: Tr,
    Option< <T as Tr>::Out >: Copy,
{
    1
}

fn main() {
    println("{}", f(1u8));
}
VL
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 30; exec @ARGV' "$V" fmt main.vl > out.txt 2>&1
grep -q 'Option <' main.vl && { echo "fmt wrote: $(grep 'Copy' main.vl)"; exit 1; }
grep -q 'Option<' main.vl || { echo "fmt lost the line: $(cat out.txt)"; exit 1; }
exit 0
