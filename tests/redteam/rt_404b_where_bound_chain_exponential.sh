#!/bin/sh
# RT-404's family, from the review of g302oblig-m2 (C1, forms fdepthtup_N): an
# impl whose `where` clause proves the level below again, `impl<T: Tr> Tr
# for W<T> where P<T>: Tr`, was exponential once the clause was required
# (1.15 s at depth 20, 33.8 s at 25); select records every answer about
# concrete types, nested ones too, so it is linear. It passes when check
# accepts the program, nested 40 deep, within 20 s.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=40
{
  echo 'trait Tr {'
  echo '    fn d(&self) -> i64;'
  echo '}'
  echo 'struct W<T> {'
  echo '    t: T,'
  echo '}'
  echo 'struct P<T> {'
  echo '    t: T,'
  echo '}'
  echo 'impl Tr for i64 {'
  echo '    fn d(&self) -> i64 {'
  echo '        0'
  echo '    }'
  echo '}'
  echo 'impl<T: Tr> Tr for P<T> {'
  echo '    fn d(&self) -> i64 {'
  echo '        0'
  echo '    }'
  echo '}'
  echo 'impl<T: Tr> Tr for W<T>'
  echo '    where'
  echo '        P<T>: Tr,'
  echo '{'
  echo '    fn d(&self) -> i64 {'
  echo '        1 + self.t.d()'
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
