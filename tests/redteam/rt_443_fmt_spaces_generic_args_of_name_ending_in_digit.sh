#!/bin/sh
# XFAIL: RT-443: `volec fmt` lays out the arguments of a type whose name ends in a digit as a comparison: `impl<'a> Deref for W2<'a>` becomes `W2 < 'a >`, and `fn f(w: W3<i64>) -> W3<i64>` becomes `W3 < i64 >` (W, Wx, Wa2b are kept) (0.30.2)
# rustfmt keeps `W2<'a>`. From the paused g302temps work (PAUSED.md,
# findings not yet reported: "fmt mangles impl<'a> Deref for W2<'a>");
# the digit at the name's end is the trigger, found while checking it.
# Since v0.30.1 at least (the same output). Layout only: the program
# checks the same after. It passes when fmt keeps `W2<'a>` and `W3<i64>`.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
struct W2<'a>(&'a i64);

impl<'a> std::ops::Deref for W2<'a> {
    type Target = i64;

    fn deref(&self) -> &i64 {
        self.0
    }
}

struct W3<T> {
    t: T,
}

fn f(w: W3<i64>) -> W3<i64> {
    w
}

fn main() {}
VL
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 30; exec @ARGV' "$V" fmt main.vl > out.txt 2>&1
bad=$(grep -n -E 'W[23] <' main.vl)
[ -n "$bad" ] && { echo "fmt wrote: $bad"; exit 1; }
grep -q "for W2<'a> {" main.vl || { echo "fmt lost the impl line: $(cat out.txt)"; exit 1; }
grep -q 'fn f(w: W3<i64>) -> W3<i64> {' main.vl || { echo "fmt lost the fn line: $(cat out.txt)"; exit 1; }
exit 0
