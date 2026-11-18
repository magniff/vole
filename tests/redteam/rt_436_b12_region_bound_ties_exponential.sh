#!/bin/sh
# From the re-review 2 of g302oblig-m2 (C, forms b12_exp_present_N): the
# regions pass's impl_bound_ties walked an instance's bound `T: P0` through
# bounds shaped like a Fibonacci tree (`impl<X: P1 + Q1> P0 for X`,
# `impl<X: P1> Q0 for X`) by every path, 2^depth of them: past 60 s at
# depth 40 and at 127. Each reference with the same inputs is met
# once per signature now (Sig.met, the regions memo of RT-404, which
# closes this form as well). It passes when the program, 127
# levels deep, builds and prints 4 within 10 s.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=127
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
  echo "impl P$n for i64 {}"
  echo "impl Q$n for i64 {}"
  echo 'fn need<T: P0>() -> i64 {'
  echo '    4'
  echo '}'
  echo 'fn main() {'
  echo '    println("{}", need::<i64>());'
  echo '}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" main.vl -o main > out.txt 2>&1
rc=$?
if [ $rc -ne 0 ]; then echo "the build did not end within 10 s or failed (rc $rc)"; tail -3 out.txt; exit 1; fi
out=$(./main)
if [ "$out" != "4" ]; then echo "printed '$out', not 4"; exit 1; fi
exit 0
