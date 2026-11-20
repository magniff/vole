#!/bin/sh
# XFAIL: RT-135: a large all-zero static is written into the binary's data (16 MB of zeros) instead of zero-fill (bss) (0.30.2)
# RT-135: `static mut`-free, safe: `static Z: [u8; 1 << 24] = [0; 1 << 24];`
# makes a binary over 16 MB with vole; rustc and cc put it in a
# zero-fill section and the binary stays small. Passes when the binary is
# under 2 MB and the program prints the right sum. Found by the review of
# g302std; v0.30.1 too. Usage: rt_135_zero_static_in_data.sh VOLEC.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/z.vl" <<'VL'
static Z: [u8; 1 << 24] = [0; 1 << 24];
fn main() {
    let mut s: u64 = 0;
    let mut i = 0usize;
    while i < Z.len() {
        s += Z[i] as u64;
        i += 4096;
    }
    println("{} {}", Z.len(), s);
}
VL
"$V" "$w/z.vl" -o "$w/z" || { echo "does not build"; exit 1; }
out=$("$w/z")
[ "$out" = "16777216 0" ] || { echo "prints '$out', want '16777216 0'"; exit 1; }
size=$(wc -c < "$w/z" | tr -d ' ')
echo "binary: $size bytes"
[ "$size" -lt 2097152 ] || { echo "the zeros are in the binary"; exit 1; }
