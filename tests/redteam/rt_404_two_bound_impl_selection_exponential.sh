#!/bin/sh
# XFAIL: RT-404: selection is exponential in the nesting depth when an impl has two bounds per level, `impl<T: Tr + Tr2> Tr for W<T>` and the same for Tr2: `check` of `go(&w)` with w a W nested 26 deep does not end within 20 s (about 2x per level: 0.9 s at 20, 3.4 s at 22, 14 s at 24); rustc is instant (0.30.2)
# From the review of g302oblig-m2 (forms fexp_16, fexp_20, fexp_22).
# Since v0.30.1 at least (v0.30.1: 1.9 s at 16, 25 s at 20); the release
# build is faster but still doubles per level. The growth fits two proofs
# of the level below per level with no result kept (inferred from the
# times, not traced). It
# passes when check accepts the program within 20 s. RT-353 is the same
# growth through a supertrait diamond.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=26
{
  echo 'trait Tr {'
  echo '    fn d(&self) -> i64;'
  echo '}'
  echo 'trait Tr2 {'
  echo '    fn e(&self) -> i64;'
  echo '}'
  echo 'struct W<T> {'
  echo '    t: T,'
  echo '}'
  echo 'impl Tr for i64 {'
  echo '    fn d(&self) -> i64 {'
  echo '        0'
  echo '    }'
  echo '}'
  echo 'impl Tr2 for i64 {'
  echo '    fn e(&self) -> i64 {'
  echo '        0'
  echo '    }'
  echo '}'
  echo 'impl<T: Tr + Tr2> Tr for W<T> {'
  echo '    fn d(&self) -> i64 {'
  echo '        1 + self.t.d()'
  echo '    }'
  echo '}'
  echo 'impl<T: Tr + Tr2> Tr2 for W<T> {'
  echo '    fn e(&self) -> i64 {'
  echo '        1 + self.t.e()'
  echo '    }'
  echo '}'
  echo 'fn go<T: Tr>(t: &T) -> i64 {'
  echo '    t.d()'
  echo '}'
  printf 'fn main() {\n    let w = '
  i=0
  while [ $i -lt $n ]; do printf 'W { t: '; i=$((i + 1)); done
  printf '0i64'
  i=0
  while [ $i -lt $n ]; do printf ' }'; i=$((i + 1)); done
  echo ';'
  echo '    println("{}", go(&w));'
  echo '}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 20; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 0 ]; then echo "check did not end within 20 s or failed (rc $rc)"; tail -3 out.txt; exit 1; fi
exit 0
