#!/bin/sh
# The compiler's own self-tests (0.27.7): `volec __selftest NAME` runs a
# check of base that no program can reach. freeze: a write to a buffer
# buf_done froze must stop the compiler with the internal error and exit
# status 1 (src-buffer.md, frozen buffers), never write it.
#
# usage: tests/selftest.sh [-c COMPILER]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
C="$ROOT/target/volec"
[ "${1:-}" = "-c" ] && C=$2
[ -x "$C" ] || { echo "selftest: no compiler at $C"; exit 2; }
fail=0

out=$("$C" __selftest freeze 2>&1)
rc=$?
want='error: internal: a write to a frozen buffer (buf_done), buffer '
case "$out" in
    "$want"[0-9]*) ;;
    *) echo "FAIL selftest freeze: printed: $out"; fail=1 ;;
esac
if [ $rc -ne 1 ]; then
    echo "FAIL selftest freeze: exit $rc, not 1"
    fail=1
fi
[ $fail -eq 0 ] && echo "selftest: freeze ok"
exit $fail
