#!/bin/sh
# (0.30.2, from RT-138's fix) Integer literals in a tuple type whose parts
# are shared, 20 levels 3 wide and 4 wide (`let a1 = (a0, a0, a0); ...`),
# read as an i64. 0.30.2's integer variables (F18.5) leave the literals
# free until the function's end, so infer.vl's walks of the type, each to
# depth 16 (subst, mentions_at; occurs, first_int, first_general,
# holds_at, may_equal_at the same way), met 3^16 or 4^16 parts per call
# as a tree: the release's check ran 51 s for the 3-wide form and past a
# minute for the 4-wide one (v0.30.1: 5 s and past a minute, in its
# widening checks). Each walk answers a (part, depth) once now (infer.vl's
# Walk). The function has a second error, so its body is not placed: the
# value itself holds 2 * 3^20 integers. It passes when `volec check` of
# each ends within 10 s with that error.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
for wide in 3 4; do
  {
    echo 'fn main() {'
    echo '    let a0 = (1, 2);'
    i=1
    while [ $i -le 20 ]; do
      p=a$((i - 1))
      parts=$p
      k=1
      while [ $k -lt $wide ]; do parts="$parts, $p"; k=$((k + 1)); done
      echo "    let a$i = ($parts);"
      i=$((i + 1))
    done
    echo '    let x: i64 = (a20.0).0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0 .0;'
    echo '    println("{}", x);'
    echo '    let z: bool = 1u8;'
    echo '}'
  } > "$w/main$wide.vl"
  (cd "$w" && VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" check "main$wide.vl" > "out$wide.txt" 2>&1)
  rc=$?
  if [ $rc -ne 1 ]; then echo "$wide wide: check did not end within 10 s with an error (rc $rc)"; tail -3 "$w/out$wide.txt"; exit 1; fi
  if ! grep -q "expected 'bool', got 'u8'" "$w/out$wide.txt"; then echo "$wide wide: not the bool error:"; tail -3 "$w/out$wide.txt"; exit 1; fi
done
exit 0
