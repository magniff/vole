#!/bin/sh
# XFAIL: RT-276: `volec fmt` rewrites a file the parser refuses: rt_093's `-> <<T as Conv>::Out as Conv>::Out` becomes `-><<T ...` and `= <<i64 ...` becomes `=<<i64 ...` (0.30.2)
# fmt must refuse a file with a parse error (say so, change nothing), as
# rustfmt does. Found when the fmt suite's tree check called
# tests/run/rt_093_qualified_path_double_angle.vl unformatted; v0.30.1 the same.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/a.vl" <<'VL'
trait Conv {
    type Out;
}

fn roundtrip<T: Conv>(t: T) -> <<T as Conv>::Out as Conv>::Out
where
    T::Out: Conv,
{
    loop {}
}

fn main() {
    let m = <<i64 as Conv>::Out as Conv>::make();
}
VL
cp "$w/a.vl" "$w/orig.vl"
VOLE_CACHE=off "$V" fmt "$w/a.vl" > "$w/out" 2>&1
rc=$?
if ! cmp -s "$w/a.vl" "$w/orig.vl"; then
    echo "FAIL: fmt changed a file that does not parse (exit $rc):"
    diff "$w/orig.vl" "$w/a.vl" | head -8
    exit 1
fi
if [ $rc -eq 0 ]; then
    echo "FAIL: fmt exited 0 on a file that does not parse"
    exit 1
fi
echo "ok: refused: $(head -1 "$w/out")"
