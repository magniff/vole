#!/bin/sh
# XFAIL: RT-260: a program's file whose path ends in `std/ptr.vl` gets std::ptr's raw-pointer index exemption: `unsafe { q[1] = 7 }` of a `*mut i64` builds there and is E0608 anywhere else (0.30.2)
# RT-260: front/check/synth_mode.vl in_std_module takes a position to be in
# std's `ptr` module when its file's path ends with `std/ptr.vl`, a
# path string: a program at m/std/ptr.vl (or m/xstd/ptr.vl) indexes a thin
# raw pointer, MVS's arithmetic, where m/other/ptr.vl gets "cannot index
# into a value of type '*mut i64'" (rustc E0608 for both). Identity from a
# name. From the review of g302index; v0.30.1 the same. Passes when the two
# files are refused alike.
# Usage: rt_260_std_ptr_path_exemption.sh VOLEC (default volec).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
mkdir -p "$w/m/std" "$w/m/other"
cat > "$w/m/std/ptr.vl" <<'VL'
fn main() {
    let mut a = [1i64, 2, 3];
    let q = &mut a[0] as *mut i64;
    // UNSAFE: the case's raw pointer index
    // SAFETY: q points to a[0] of a live array of 3
    unsafe {
        q[1] = 7;
    }
    println("{}", a[1]);
}
VL
cp "$w/m/std/ptr.vl" "$w/m/other/ptr.vl"
cd "$w" || exit 2
std_ok=0
other_ok=0
VOLE_CACHE=off "$V" m/std/ptr.vl -o std.bin > std.out 2>&1 && std_ok=1
VOLE_CACHE=off "$V" m/other/ptr.vl -o other.bin > other.out 2>&1 && other_ok=1
if [ $std_ok = 0 ] && [ $other_ok = 0 ]; then
    echo "ok: both refused: $(grep -m1 error std.out)"
    exit 0
fi
if [ $std_ok = 1 ] && [ $other_ok = 1 ]; then
    echo "FAIL: both build: a raw pointer is indexed in a program (rustc E0608)"
    exit 1
fi
if [ $std_ok = 1 ]; then
    echo "FAIL: m/std/ptr.vl builds, m/other/ptr.vl is refused: $(grep -m1 error other.out)"
else
    echo "FAIL: m/other/ptr.vl builds, m/std/ptr.vl is refused: $(grep -m1 error std.out)"
fi
exit 1
