#!/bin/sh
# XFAIL: RT-239: a #[test] that calls main() calls the test runner's main and recurses until SIGSEGV (0.30.2)
# The test build renames only main's definition token, so a call of main()
# in a test resolves to the runner's own main. In Rust a test calling main()
# calls the program's main: the test passes and prints "hi".
set -u
VOLEC=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
printf 'fn main() -> i32 {\n    println("hi");\n    0\n}\n\n#[test]\nfn t() {\n    assert_eq(main(), 0);\n}\n' >"$T/main.vl"
for o in 0 2; do
    out=$(cd "$T" && perl -e 'alarm 120; exec @ARGV' "$VOLEC" test -O$o main.vl 2>&1)
    rc=$?
    [ $rc -eq 0 ] || { echo "FAIL: -O$o exit $rc: $(echo "$out" | tail -3)"; exit 1; }
done
echo ok
