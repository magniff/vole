#!/bin/sh
# XFAIL: RT-136: the match usefulness check is cubic in the number of arms: 1000 integer arms take 5-7 s to check, 5000 over two minutes (0.30.2)
# RT-136 (R302C-34): the match usefulness check is cubic in the number of arms: a
# match of N integer literal arms takes ~N^3 to check (1000 arms 5-7 s,
# 5000 arms over 2 minutes at -O0 and -O2; rustc: well under a second).
# The test compares two sizes: the check's CPU time (user + system) at
# 2400 arms over its CPU time at 800 arms, each less the CPU time of a
# 1-arm program (the start), must stay under 15 (quadratic is 9; cubic
# is 27). CPU time, not wall time: a load that rises during one of the
# two readings slows that reading alone, and with wall times at 400 and
# 1200 arms the ratio crossed 15 both ways (an XPASS of the cubic check
# at load 2 to 14; 800 and 2400 arms in wall time gave 24.7 at load 14
# and 8.4 at load 44). 800 arms, not 400, keeps the small reading near
# 0.5 s, well above the timer's noise.
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
# cpu FILE: the CPU time, in seconds, of `volec check FILE`
cpu() {
    VOLE_CACHE=off perl -e 'alarm 600; system("sh", "-c", "exec \"\$0\" check \"\$1\" >/dev/null 2>&1", @ARGV); @t = times; printf "%.3f\n", $t[2] + $t[3]' "$V" "$1"
}
gen 1; gen 800; gen 2400
z=$(cpu "$w/m1.vl")
a=$(cpu "$w/m800.vl")
b=$(cpu "$w/m2400.vl")
perl -e '($z, $a, $b) = @ARGV; $a -= $z; $b -= $z; $r = $b / ($a > 0.02 ? $a : 0.02); printf "check CPU time (less %.2f s start): 800 arms %.2f s, 2400 arms %.2f s, ratio %.1f (want < 15)\n", $z, $a, $b, $r; exit($r < 15 ? 0 : 1)' "$z" "$a" "$b"
