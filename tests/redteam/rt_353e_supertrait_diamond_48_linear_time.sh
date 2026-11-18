#!/bin/sh
# (0.30.2, RT-353) A supertrait diamond 48 deep (T_i: T_{i-1} + T_{i-2}):
# `Y::top(y)`, `y.top()`, `Y::K`, `Y::Out` and a bound `Z: T0` proved from
# `Y: T47` check in linear time. Every walk of the supertraits meets each
# trait once (traits::super_closure, obligations::elaborate,
# regions::super_refs); a walk without its visited set takes about 2^(n/2)
# steps (23 s at depth 40 on a build with super_closure's set planted out,
# where the fixed build takes 0.05 s). The alarm of 10 s leaves the
# fixed build two orders of magnitude; the exponential one needs hours.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=48
{
  echo 'trait T0 {'
  echo '    const K: i64;'
  echo '    type Out;'
  echo '    fn top(&self) -> i64;'
  echo '}'
  echo 'trait T1: T0 {}'
  i=2
  while [ $i -lt $n ]; do echo "trait T$i: T$((i - 1)) + T$((i - 2)) {}"; i=$((i + 1)); done
  echo 'struct S;'
  echo 'impl T0 for S {'
  echo '    const K: i64 = 5;'
  echo '    type Out = i64;'
  echo '    fn top(&self) -> i64 {'
  echo '        3'
  echo '    }'
  echo '}'
  i=1
  while [ $i -lt $n ]; do echo "impl T$i for S {}"; i=$((i + 1)); done
  echo 'fn need<Z: T0>(z: &Z) -> i64 {'
  echo '    z.top()'
  echo '}'
  echo "fn k<Y: T$((n - 1))>(y: &Y, o: Y::Out) -> Y::Out {"
  echo '    let _ = Y::top(y) * 100 + y.top() * 10 + Y::K + need(y);'
  echo '    o'
  echo '}'
  echo 'fn main() {'
  echo '    println("{}", k(&S, 9));'
  echo '}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" main.vl -o prog > out.txt 2>&1
rc=$?
if [ $rc -ne 0 ]; then echo "the build did not end within 10 s or failed (rc $rc)"; tail -3 out.txt; exit 1; fi
out=$(./prog)
if [ "$out" != "9" ]; then echo "printed '$out', rustc prints 9"; exit 1; fi
exit 0
