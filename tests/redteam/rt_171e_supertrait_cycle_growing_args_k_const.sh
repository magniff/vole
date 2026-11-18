#!/bin/sh
# (0.30.2, the re-review of the qualified paths) A supertrait cycle whose
# arguments grow at each step (`trait A<T>: B<Option<T>>`, `trait B<T>:
# A<Option<T>>`), walked by `X::K`, A's constant, under `X: A<u8>`: the
# cycle is error trait.cycle (rustc E0391) and the checking ends there. The
# branch before the fix grew without end (748 MB in 10 s): a walk keyed by
# (trait, arguments) never met the same pair twice. Also: a query, which
# goes on after the program's errors, ends (the bound that closes the
# cycle names no trait after the error).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
trait A<T>: B<Option<T>> {
    const K: i64;
    fn a(&self) -> i64;
}

trait B<T>: A<Option<T>> {
    fn b(&self) -> i64;
}

fn k<X: A<u8>>(x: &X) -> i64 {
    X::K
}

fn main() {
    println("x");
}
VL
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 20; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 1 ]; then echo "check did not report an error within 20 s (rc $rc: 0 accepted, 142 timed out)"; tail -3 out.txt; exit 1; fi
if ! grep -q 'error\[trait.cycle\]' out.txt || [ "$(grep -c 'error' out.txt)" -ne 1 ]; then
    echo "expected the one error trait.cycle:"; cat out.txt; exit 1
fi
VOLE_CACHE=off perl -e 'alarm 20; exec @ARGV' "$V" query type main.vl:11:5 > q.txt 2>&1
rc=$?
if [ $rc -gt 1 ]; then echo "query type did not end within 20 s (rc $rc)"; tail -3 q.txt; exit 1; fi
exit 0
