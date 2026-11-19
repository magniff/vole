#!/bin/sh
# (0.30.2, from RT-138's fix) A type whose parts are shared, 30 nested
# pairs (`let a1 = (a0, a0); ...`), is 2^30 nodes as a tree: every
# has_error_type of it walked them all (v0.30.1 too: past 60 s at 24
# levels), from a method's lookup on it. has_error_type walks a type
# past 256 nodes as a graph now, each type once. It passes when `volec
# check` ends within 10 s (with the nesting limit's error, as the clone's
# instance is too big).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
{
  echo 'fn main() {'
  echo '    let a0 = (1u8, 2u8);'
  i=1
  while [ $i -le 30 ]; do
    echo "    let a$i = (a$((i - 1)), a$((i - 1)));"
    i=$((i + 1))
  done
  echo '    let b = a30.clone();'
  echo '    println("{}", (b.0).1 .0);'
  echo '}'
} > "$w/main.vl"
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 0 ] && [ $rc -ne 1 ]; then echo "check did not end within 10 s (rc $rc)"; tail -3 out.txt; exit 1; fi
exit 0
