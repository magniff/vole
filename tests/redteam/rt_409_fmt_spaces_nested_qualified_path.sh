#!/bin/sh
# XFAIL: RT-409: `volec fmt` lays out a qualified path whose self type has nested generics, `type Out = <W<W<T>> as H>::Out;`, as `< W<W<T>> as H >::Out` (0.30.2)
# rustfmt keeps `<W<W<T>> as H>::Out`. Seen when the edit hook formatted rt_400.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
trait H {
    type Out;
}

struct W<T> {
    t: T,
}

impl H for i64 {
    type Out = i64;
}

impl<T: H> H for W<T> {
    type Out = <W<W<T>> as H>::Out;
}

fn main() {}
VL
cd "$w" || exit 1
VOLE_CACHE=off perl -e 'alarm 30; exec @ARGV' "$V" fmt main.vl > out.txt 2>&1
grep -q 'type Out = <W<W<T>> as H>::Out;' main.vl || { echo "fmt wrote: $(grep 'type Out = <' main.vl)"; exit 1; }
exit 0
