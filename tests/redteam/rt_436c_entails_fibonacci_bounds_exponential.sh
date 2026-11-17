#!/bin/sh
# From the re-review of g302oblig-m2 (C3, forms b18_exp_generic_holds_N):
# coherence::entails, once its limit was the impl search's (127, RT-436),
# proved `W<T>: Sup` through bounds shaped like a Fibonacci tree (`impl<X:
# P2 + Q2> P1 for X`, `impl<X: P2> Q1 for X`) in 2^depth steps: 52 s at
# depth 40 (rustc: 0.15 s). Each goal (impl, node, trait) is answered once
# per ask now (entails_memo). It passes when check accepts the program,
# 120 levels deep, within 10 s.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=120
{
  i=0
  while [ $i -le $n ]; do
    echo "trait P$i {}"
    echo "trait Q$i {}"
    i=$((i + 1))
  done
  i=0
  while [ $i -lt $n ]; do
    j=$((i + 1))
    echo "impl<X: P$j + Q$j> P$i for X {}"
    echo "impl<X: P$j> Q$i for X {}"
    i=$j
  done
  echo 'trait Sup {}'
  echo 'trait Tr: Sup {}'
  echo 'struct W<T> {'
  echo '    t: T,'
  echo '}'
  echo 'impl<T: P0> Sup for W<T> {}'
  echo "impl<T: P$n + Q$n> Tr for W<T> {}"
  echo 'fn main() {}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 0 ]; then echo "check did not end within 10 s or failed (rc $rc)"; tail -3 out.txt; exit 1; fi
exit 0
