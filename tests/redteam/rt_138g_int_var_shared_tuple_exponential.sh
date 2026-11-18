#!/bin/sh
# XFAIL: RT-138g: integer literals in a shared tuple type 3 wide and 20 deep: check runs past 30 s (infer::subst and mentions_at walk it as a tree, 3^16 nodes); v0.30.1 took about 5 s (0.30.3)
# (from RT-138's fix) `let a1 = (a0, a0, a0); ...` 20 levels of a tuple of
# integer literals. 0.30.2's integer variables (F18.5) leave the literals
# free until the function's end, so infer.vl's walks over the type, each
# bounded by depth 16 but a tree walk of a shared type (subst,
# mentions_at; first_int, first_general, holds_at, may_equal_at the same
# way), meet 3^16 nodes per call. It passes when `volec check` ends
# within 10 s.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
{
  echo 'fn main() {'
  echo '    let a0 = (1, 2);'
  i=1
  while [ $i -le 20 ]; do
    p=a$((i - 1))
    echo "    let a$i = ($p, $p, $p);"
    i=$((i + 1))
  done
  echo '    let x: i64 = (a20.0).0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0;'
  echo '    println("{}", x);'
  echo '}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 0 ] && [ $rc -ne 1 ]; then echo "check did not end within 10 s (rc $rc)"; tail -3 out.txt; exit 1; fi
exit 0
