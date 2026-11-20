#!/bin/sh
# XFAIL: RT-450: `volec check FILE --emit-places=regions` panics (places/borrowck/mod.vl:476: index out of bounds: index 4, length 4, exit 101) on a program whose `let f: fn(&i64) = keep;` (keep taking `&'static i64`) is refused with borrowck.fn_value_static; plain `check` and the build report the error without a crash (0.30.2)
# From the review of g302fnval (its p/stale.vl). Since v0.30.1 at least
# (the same panic). rustc refuses the program (E0308). It passes when
# the check with --emit-places=regions ends within 30 s with exit 0 or 1
# and prints no "index out of bounds" and no "panic".
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
fn keep(_x: &'static i64) {}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    v.push(1);
    let f: fn(&i64) = keep;
    let r = &v[0];
    f(r);
}
VL
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 30; exec @ARGV' "$V" check main.vl --emit-places=regions > out.txt 2>&1
rc=$?
if grep -q -i -E 'index out of bounds|panic' out.txt; then
    echo "check --emit-places=regions crashed (exit $rc): $(grep -i -E 'index out of bounds|panic' out.txt | head -1)"
    exit 1
fi
[ $rc -eq 0 ] || [ $rc -eq 1 ] || { echo "check exit $rc"; tail -2 out.txt; exit 1; }
exit 0
