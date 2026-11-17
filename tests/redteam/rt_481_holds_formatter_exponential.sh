#!/bin/sh
# XFAIL: RT-481: `check` time doubles with each level of a struct chain where each level holds the next twice and a `&'a N0<'a>` back to the first, read through a static (front::effects::infer::holds_formatter, exponential): 26 levels take about 14 s of CPU on the release build and on v0.30.1, 24 levels 4 s, 28 levels 46 s; rustc is instant (0.30.2)
# From the third re-review of g302holes (its forms h_static_dN, gen_h.py).
# tests/outlives_depth.sh notes the same function over a recursive group.
# Measured in CPU time (user + system), so that the machine's load does not
# decide it: it passes when `check` of 26 levels takes under 5 s of CPU.
# usage: run.sh VOLEC  (exit 0 when check is fast)
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
d=26
{
    i=0
    while [ $i -lt $d ]; do
        echo "struct N$i<'a> { r: Option<&'a N0<'a>>, a: N$((i + 1))<'a>, b: N$((i + 1))<'a> }"
        i=$((i + 1))
    done
    echo "struct N$d<'a> { r: Option<&'a N0<'a>>, v: i64 }"
    echo "static S: Option<&'static N0<'static>> = None;"
    echo 'fn main() { println("{}", S.is_none()); }'
} > "$w/h.vl"
VOLE_CACHE=off perl -e '
    $SIG{ALRM} = sub { kill "KILL", $pid; };
    $pid = fork();
    if ($pid == 0) { open STDOUT, ">", "/dev/null"; open STDERR, ">", "/dev/null"; exec @ARGV; }
    alarm 120;
    waitpid($pid, 0);
    $rc = $? & 127 ? "killed" : $? >> 8;
    @t = times;
    $c = $t[2] + $t[3];
    printf "check of %d levels: %.2f s of CPU, exit %s (want under 5 s, exit 0)\n", '"$d"', $c, $rc;
    exit($c < 5 && $rc eq "0" ? 0 : 1);
' "$V" check "$w/h.vl"
