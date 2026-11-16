#!/bin/sh
# XFAIL: RT-136: the match usefulness check is cubic in the number of arms: 1000 integer arms take 5-7 s to check, 5000 over two minutes (0.30.2)
# RT-136 (R302C-34): the match usefulness check is cubic in the number of arms: a
# match of N integer literal arms takes ~N^3 to check (1000 arms 5-7 s,
# 5000 arms over 2 minutes at -O0 and -O2; rustc: well under a second).
# The test compares two sizes, so that the machine's load cancels out:
# the check time at 1200 arms over the time at 400 arms, each less the
# time of a 1-arm program (the start), must stay under 15 (quadratic is
# 9; cubic is 27).
# usage: run.sh VOLEC  (exit 0 when the growth is at most quadratic)
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
gen() {
    n=$1
    {
        echo 'fn main() {'
        echo '    let n = std::env::args().count() as i64;'
        echo '    let r = match n {'
        i=0
        while [ $i -lt $n ]; do echo "        $i => $((i * 3)),"; i=$((i + 1)); done
        echo '        _ => -1,'
        echo '    };'
        echo '    println("{r}");'
        echo '}'
    } > "$w/m$n.vl"
}
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
gen 1; gen 400; gen 1200
t0=$(now); VOLE_CACHE=off "$V" check "$w/m1.vl" >/dev/null 2>&1; t1=$(now)
VOLE_CACHE=off "$V" check "$w/m400.vl" >/dev/null 2>&1; t2=$(now)
VOLE_CACHE=off perl -e 'alarm 600; exec @ARGV' "$V" check "$w/m1200.vl" >/dev/null 2>&1; t3=$(now)
perl -e '($z, $a, $b) = @ARGV; $a -= $z; $b -= $z; $r = $b / ($a > 0.02 ? $a : 0.02); printf "check (less %.2f s start): 400 arms %.2f s, 1200 arms %.2f s, ratio %.1f (want < 15)\n", $z, $a, $b, $r; exit($r < 15 ? 0 : 1)' "$(echo "$t1 - $t0" | bc)" "$(echo "$t2 - $t1" | bc)" "$(echo "$t3 - $t2" | bc)"
