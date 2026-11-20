#!/bin/sh
# XFAIL: RT-138h: an error that names a type whose parts are shared prints it as a tree (front/types.vl buf_type): 3^20 parts, past 40 s; v0.30.1 too (0.30.3)
# (from RT-138's fix) `if c { a20 } else { b20 }` of two 20-level tuple
# types, 3 wide, one of integers and one of bools: unify and the
# inference walks end at once, then the mismatch's message writes both
# types out whole. rustc shortens a long type in a message (and writes it
# to a file). It passes when `volec check` ends within 10 s with an error.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
{
  echo 'fn pick(c: bool) {'
  echo '    let a0 = (1, 2);'
  echo '    let b0 = (true, false);'
  i=1
  while [ $i -le 20 ]; do
    p=$((i - 1))
    echo "    let a$i = (a$p, a$p, a$p);"
    echo "    let b$i = (b$p, b$p, b$p);"
    i=$((i + 1))
  done
  echo '    let x = if c { a20 } else { b20 };'
  echo '}'
  echo 'fn main() {'
  echo '    pick(true);'
  echo '}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 1 ]; then echo "check did not end within 10 s with an error (rc $rc)"; exit 1; fi
exit 0
