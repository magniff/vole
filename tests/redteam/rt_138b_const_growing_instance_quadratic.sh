#!/bin/sh
# (0.30.2, from RT-138's fix) A generic constant naming itself at a bigger
# type each time, `impl<T> W<T> { const P: usize = W::<W<T>>::P + 1; }`,
# makes W<W<..>> until the nesting limit (a tree of 4096 types) refuses
# it: v0.30.1 said so in 0.5 s. The release ran for minutes after it:
# obligations::concrete asked has_error_type at each level of each such
# type, quadratic in its depth, for each of the 4096 instances. concrete
# looks at each node once now, at most 4096 of them. It passes when
# `volec check` ends within 10 s with the nesting error.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
struct W<T> {
    x: T,
}
impl<T> W<T> {
    const P: usize = W::<W<T>>::P + 1;
}
fn main() {
    println("{}", W::<i32>::P);
}
VL
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 10; exec @ARGV' "$V" check main.vl > out.txt 2>&1
rc=$?
if [ $rc -ne 1 ]; then echo "check did not end within 10 s with an error (rc $rc)"; tail -3 out.txt; exit 1; fi
if ! grep -q 'type arguments nested too deeply' out.txt; then echo "no nesting error:"; tail -3 out.txt; exit 1; fi
exit 0
