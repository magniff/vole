#!/bin/sh
# std moves as a program does (0.25.2): the parts of owned values that a
# function cannot take, outside std's containers and iterators. Until
# 0.25.2 std was exempt: in std, `let x = m.functions[h];` of an owned
# element was a copy of its bits that the scope dropped while the
# collection still owned it (std::gpu::wgsl freed parts of its module on
# every translation), and `Some(v[i])`, `return x` were silent copies too,
# owned twice. Now `let x = part;` borrows in std as in a program (D13),
# and a move out of a part is own.move_out, except in std's root,
# std::iter and std::collections, which move elements by their bits by
# hand (front/modules std_moves_bits).
#
# The check: a copy of std's tree with probe functions appended to a
# module of each kind, checked with --std-tree; each probe's error (or
# none) is as listed. Prints `pass std-moves` or `FAIL std-moves` and why.
#
# usage: tests/std/moves.sh [-c COMPILER]

set -u
LC_ALL=C
export LC_ALL
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        *) echo "usage: tests/std/moves.sh [-c COMPILER]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
WORK=$(mktemp -d "${TMPDIR:-/tmp}/std-moves.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

cp -R "$ROOT/compiler/std" "$WORK/std"
# (a module of std's own code: as a program)
cat >>"$WORK/std/cli.vl" <<'EOF'

// probes of tests/std/moves.sh
fn zz_probe_keep(v: Vec<String>) -> String {
    let x = v[0];
    x
}

fn zz_probe_some(v: Vec<String>) -> Option<String> {
    Some(v[0])
}

fn zz_probe_read(v: Vec<String>) -> usize {
    let x = v[0];
    x.len()
}
EOF
# (std::collections: moves by bits, by hand)
cat >>"$WORK/std/collections/mod.vl" <<'EOF'

// probes of tests/std/moves.sh
fn zz_probe_bits(v: Vec<String>) -> Option<String> {
    Some(v[0])
}
EOF
printf 'fn main(gpa: Gpa) {\n    let v: Vec<i64> = Vec::new_in(gpa);\n}\n' >"$WORK/main.vl"
VOLE_OK=0 "$COMPILER" check --std-tree "$WORK/std" "$WORK/main.vl" >"$WORK/out" 2>&1
sed -n 's|^.*/std/\([^:]*\):\([0-9]*\):[0-9]*: error\[\([^]]*\)\] \([^|]*\).*|\1:\2 \3 \4|p' \
    "$WORK/out" >"$WORK/errors"

bad=""
line() { # <file> <text>: the line of text in the probe file
    grep -n "^$2\$" "$WORK/std/$1" | tail -1 | cut -d: -f1
}
want() { # <file> <line> <code> <words>: an error there, with those words
    if ! grep -q "^$1:$2 $3 .*$4" "$WORK/errors"; then
        bad="$bad
    $1:$2: no $3 ($4)"
    fi
}
cli_keep=$(line cli.vl '    x')
cli_some=$(line cli.vl '    Some(v\[0\])')
want cli.vl "$cli_keep" own.move_out "cannot move 'x' (String) out of a reference"
want cli.vl "$cli_some" own.move_out "cannot move 'v\[0\]' (String) out of an index"
# (nothing else: the read borrows, collections moves its bits, the rest of
# std is clean)
others=$(grep -v "^cli.vl:\($cli_keep\|$cli_some\) " "$WORK/errors")
if [ -n "$others" ]; then
    bad="$bad
$(printf '%s\n' "$others" | sed 's/^/    unexpected: /')"
fi
if [ -z "$bad" ]; then
    echo "pass std-moves"
else
    echo "FAIL std-moves: std's moves are not checked as a program's:$bad"
    sed 's/^/    | /' "$WORK/out"
fi
exit 0
