#!/bin/sh
# XFAIL: RT-353: through a supertrait diamond chain (T_i: T_{i-1} + T_{i-2}), `y.top()` under `Y: T33` is refused from depth 18 on ("no method 'top' on type parameter 'Y'", rustc prints 3), and on a build that accepts it `check` time grows exponentially (about 9 s at depth 34; v0.30.1 59 s at 32) (0.30.2)
# The time is in front::obligations (param_candidate, param_preds, select).
# From the re-review of the qualified-path work. It passes when check
# accepts the program within 20 s; rustc is instant.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=34
{
  echo 'trait T0 {'
  echo '    fn top(&self) -> i64;'
  echo '}'
  echo 'trait T1: T0 {}'
  i=2
  while [ $i -lt $n ]; do echo "trait T$i: T$((i - 1)) + T$((i - 2)) {}"; i=$((i + 1)); done
  echo 'struct S;'
  echo 'impl T0 for S {'
  echo '    fn top(&self) -> i64 {'
  echo '        3'
  echo '    }'
  echo '}'
  i=1
  while [ $i -lt $n ]; do echo "impl T$i for S {}"; i=$((i + 1)); done
  echo "fn k<Y: T$((n - 1))>(y: &Y) -> i64 {"
  echo '    y.top()'
  echo '}'
  echo 'fn main() {'
  echo '    println("{}", k(&S));'
  echo '}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 20; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 0 ]; then echo "check did not end within 20 s or failed (rc $rc)"; tail -3 out.txt; exit 1; fi
exit 0
