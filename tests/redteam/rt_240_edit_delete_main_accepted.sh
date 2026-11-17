#!/bin/sh
# XFAIL: RT-240: `volec edit delete main` removes the program's entry and its check passes (0.30.2)
# refactor rename and move of main are refused (refactor.entry); delete is
# not, and main.missing is reported only when linking. The edit must be
# refused, or its check must report the missing entry.
set -u
VOLEC=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
printf 'fn helper() -> i64 {\n    1\n}\n\nfn main() {\n    println("{}", helper());\n}\n' >"$T/main.vl"
out=$(cd "$T" && VOLE_CACHE=off "$VOLEC" edit delete main --root main.vl 2>&1)
rc=$?
if [ $rc -eq 0 ] && ! grep -q 'fn main' "$T/main.vl"; then
    echo "FAIL: main deleted and the edit passed: $(echo "$out" | tail -2)"; exit 1
fi
echo ok
