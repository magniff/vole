#!/bin/sh
# XFAIL: RT-60: volec run and volec test reuse a stale build when a source file is replaced by an older one (0.30.2)
# RT-60: `volec run` (and `volec test`) reuse their last build when a
# source file is replaced by an older one (mv, cp -p, tar, rsync -t keep
# the file's mtime): up_to_date rebuilds only when a file is newer than
# the binary, so the program run is not the one on disk.
# Usage: run.sh VOLEC. Passes when the second run prints 22.
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
d=$(mktemp -d)
cd "$d" || exit 2
mkdir -p target/volec-cache
printf 'mod m;\n\nfn main() -> i32 {\n    println("{}", m::f(2));\n    0\n}\n' > main.vl
printf 'pub fn f(x: i64) -> i64 {\n    x * 11\n}\n' > m_old.vl
touch -t 202001010000 m_old.vl
printf 'pub fn f(x: i64) -> i64 {\n    x * 13\n}\n' > m.vl
first=$(VOLE_CACHE= "$V" run 2>&1)
mv m_old.vl m.vl
second=$(VOLE_CACHE= "$V" run 2>&1)
"$V" main.vl -o fresh > /dev/null 2>&1
fresh=$(./fresh)
cd / && rm -rf "$d"
echo "first run: $first; after mv of the older m.vl: $second; a fresh build: $fresh"
[ "$second" = "22" ] || { echo "FAIL: run used the stale build"; exit 1; }
echo ok
