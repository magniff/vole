#!/bin/sh
# XFAIL: RT-462: `check` of 16 levels of supertraits with two instances each, `trait T1<X>: T0<(X, u8)> + T0<(X, u16)> {}` .. `T16`, and `fn k<X: T16<u8>>(x: &X) -> i64 { 0 }`, does not end within 10 s on the release build (33 s at a load of 22, 17-27 s in the review); v0.30.1 checks it in 1.7 s and rustc builds it in 1.7 s (0.30.2)
# From the second re-review of g302qual (its form x_pairs_exp_nobody_d16).
# A regression since the obligations work: the review traced it to
# obligations::elaborate's dedup, a linear scan over 2^16 elaborated
# bounds (not traced again here). 12 levels check in 0.3 s. It passes
# when check accepts the program within 10 s.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=16
{
  echo 'trait T0<X> {'
  echo '    fn top(&self) -> i64;'
  echo '}'
  i=1
  while [ $i -le $n ]; do
    echo ''
    echo "trait T$i<X>: T$((i - 1))<(X, u8)> + T$((i - 1))<(X, u16)> {}"
    i=$((i + 1))
  done
  echo ''
  echo "fn k<X: T$n<u8>>(x: &X) -> i64 {"
  echo '    0'
  echo '}'
  echo ''
  echo 'fn main() {'
  echo '    println("x");'
  echo '}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 0 ]; then echo "check did not end within 10 s or failed (rc $rc)"; tail -3 out.txt; exit 1; fi
exit 0
