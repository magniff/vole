#!/bin/sh
# XFAIL: RT-277: `volec fmt` is not idempotent on a long `else if` chain: each run lays out a bounded part more, so a formatted file is unformatted again (tests/run/rt_tl_006_elseif_chain_stack.vl) (0.30.2)
# fmt(fmt(x)) must equal fmt(x). Found when the fmt suite's tree check
# called rt_tl_006 unformatted right after it was formatted; v0.30.1 the same.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
{
    echo 'fn f(v: i64) -> i64 {'
    printf '    if v == 0 { 0 }'
    i=1
    while [ $i -lt 2000 ]; do printf ' else if v == %d { %d }' $i $((i % 7)); i=$((i + 1)); done
    echo ' else { 9 }'
    echo '}'
    echo 'fn main() { println("{}", f(1999)); }'
} > "$w/a.vl"
VOLE_CACHE=off "$V" fmt "$w/a.vl" > /dev/null 2>&1 || { echo "FAIL: first fmt failed"; exit 1; }
cp "$w/a.vl" "$w/once.vl"
VOLE_CACHE=off "$V" fmt "$w/a.vl" > /dev/null 2>&1 || { echo "FAIL: second fmt failed"; exit 1; }
if ! cmp -s "$w/a.vl" "$w/once.vl"; then
    echo "FAIL: fmt is not idempotent: the second run changed $(diff "$w/once.vl" "$w/a.vl" | grep -c '^[<>]') lines"
    exit 1
fi
echo ok
