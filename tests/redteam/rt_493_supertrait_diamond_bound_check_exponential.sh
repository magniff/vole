#!/bin/sh
# XFAIL: RT-493: `check` time doubles with each level of a supertrait diamond with a type argument (`trait T_i<X>: T_{i-1}<X> + U_{i-1}<X>`, `trait U_i<X>: T_{i-1}<X> + U_{i-1}<X>`) when `fn k<X: T26<u8>>(x: &X)` calls `need(x)` under `U: T0<u8>` (impl_bound_ties, exponential): 26 levels take about 15 s of CPU on the release build, 24 levels 3.4 s; v0.30.1 refuses it ("the trait 'T0<u8>' is not implemented for 'X'"); rustc builds it in 0.13 s (0.30.2)
# From the review of g302elab (its gen/diam.py, mode args). RT-353 is a
# diamond without type arguments and a method call (front::obligations).
# Measured in CPU time (user + system), so that the machine's load does not
# decide it: it passes when `check` accepts 26 levels in under 5 s of CPU.
# usage: run.sh VOLEC  (exit 0 when check accepts it quickly)
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
n=26
{
    echo 'trait T0<X> {'
    echo '    fn top(&self) -> i64;'
    echo '}'
    echo 'trait U0<X>: T0<X> {}'
    i=1
    while [ $i -le $n ]; do
        j=$((i - 1))
        echo "trait T$i<X>: T$j<X> + U$j<X> {}"
        echo "trait U$i<X>: T$j<X> + U$j<X> {}"
        i=$((i + 1))
    done
    echo 'fn need<U: T0<u8>>(u: &U) -> i64 {'
    echo '    0'
    echo '}'
    echo "fn k<X: T$n<u8>>(x: &X) -> i64 {"
    echo '    need(x)'
    echo '}'
    echo 'fn main() {'
    echo '    println("x");'
    echo '}'
} > "$w/d.vl"
VOLE_CACHE=off perl -e '
    $SIG{ALRM} = sub { kill "KILL", $pid; };
    $pid = fork();
    if ($pid == 0) { open STDOUT, ">", "/dev/null"; open STDERR, ">", "/dev/null"; exec @ARGV; }
    alarm 120;
    waitpid($pid, 0);
    $rc = $? & 127 ? "killed" : $? >> 8;
    @t = times;
    $c = $t[2] + $t[3];
    printf "check of %d levels: %.2f s of CPU, exit %s (want under 5 s, exit 0)\n", '"$n"', $c, $rc;
    exit($c < 5 && $rc eq "0" ? 0 : 1);
' "$V" check "$w/d.vl"
