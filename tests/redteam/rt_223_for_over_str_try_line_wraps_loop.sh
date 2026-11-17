#!/bin/sh
# XFAIL: RT-223: `for b in s` over a &str: the distinct.method error's try: line casts the whole for loop, `(for b in s { .. } as &[u8]).into_iter(..)` (0.30.2)
# The error is right (rustc: E0277, &str is not an iterator); the try: line
# must name the iterated expression, `s.as_bytes()` or `s.chars()`, never the loop.
set -u
VOLEC=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
printf 'fn main() {\n    let s = "ab";\n    for b in s {\n        println("{b}");\n    }\n}\n' >"$T/main.vl"
out=$("$VOLEC" check "$T/main.vl" 2>&1)
echo "$out" | grep -q 'error' || { echo "FAIL: no error"; exit 1; }
if echo "$out" | grep -q 'try: (for '; then
    echo "FAIL: the try: line casts the loop"; exit 1
fi
echo ok
