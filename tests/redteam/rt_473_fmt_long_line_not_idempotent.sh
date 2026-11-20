#!/bin/sh
# XFAIL: RT-473: `volec fmt` is not idempotent on a long line: a 500-arm `else if` chain on one line (11 KB) is left unformatted by one fmt (`fmt --check` then fails); each pass breaks about 40 more lines, 4 passes reach the fixed point (rt_tl_006's 12000 arms took about 90) (0.30.2)
# Found by the integrator on rt_tl_006_elseif_chain_stack.vl. v0.30.1 the
# same (the same 4 passes, the same result). It passes when `fmt --check`
# accepts the file right after one `fmt`: a formatter's output is its own
# fixed point (rustfmt's is).
# usage: run.sh VOLEC  (exit 0 when one fmt reaches the fixed point)
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=500
{
    echo 'fn main() -> i32 {'
    echo '    let v = 3;'
    printf '    let x = if v == 0 { 0 }'
    i=1
    while [ $i -lt $n ]; do printf ' else if v == %d { %d }' $i $((i % 7)); i=$((i + 1)); done
    echo ' else { 9 };'
    echo '    x'
    echo '}'
} > "$w/c.vl"
f() { VOLE_CACHE=off perl -e 'alarm 60; exec @ARGV' "$V" fmt "$@" >/dev/null 2>&1; }
f "$w/c.vl" || { echo "fmt failed"; exit 1; }
if f --check "$w/c.vl"; then
    echo "one fmt reaches the fixed point"
    exit 0
fi
p=1
while [ $p -lt 20 ] && ! f --check "$w/c.vl"; do f "$w/c.vl"; p=$((p + 1)); done
echo "one fmt leaves the file unformatted: $p passes to the fixed point (want 1)"
exit 1
