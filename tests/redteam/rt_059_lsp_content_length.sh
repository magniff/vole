#!/bin/sh
# XFAIL: RT-59: the LSP server panics on a Content-Length near i64::MAX; larger lengths wrap (0.30.2)
# RT-59: the LSP server panics (exit 101) on a Content-Length near
# i64::MAX: `e + 4 + len` wraps, the "not all there yet" test passes and
# the body slice is out of bounds. Usage: run.sh VOLEC (default volec).
# Passes when the server does not panic on the frame (it may refuse it,
# or close the connection with an error, but not crash).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
d=$(mktemp -d)
printf 'fn main() -> i32 {\n    0\n}\n' > "$d/main.vl"
frame() { printf 'Content-Length: %d\r\n\r\n%s' "${#1}" "$1"; }
{
    frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":"file://'"$d"'","capabilities":{}}}'
    frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
    sleep 1
    printf 'Content-Length: 9223372036854775807\r\n\r\n{}'
    sleep 1
    frame '{"jsonrpc":"2.0","id":2,"method":"shutdown"}'
    frame '{"jsonrpc":"2.0","method":"exit"}'
} | (cd "$d" && VOLE_CACHE=off "$V" lsp > "$d/out" 2> "$d/err")
rc=$?
rm -rf "$d/main.vl"
if grep -q 'out of bounds' "$d/err" || [ $rc -eq 101 ]; then
    echo "FAIL: the server panicked (exit $rc): $(tail -c 200 "$d/err")"
    rm -rf "$d"; exit 1
fi
echo "ok: exit $rc"
rm -rf "$d"; exit 0
