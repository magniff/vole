#!/bin/sh
# (0.25.3) Text blocks and embedded files where a case of tests/run cannot
# show them (docs/grammar.md, "Text blocks"):
#
#   embed_crlf          a text block in a file with CRLF line breaks (the
#                       tree's files are LF, fmt's): its value's line
#                       breaks are '\n', a joined line's too
#   embed_message       embed.missing names the path it tried, relative to
#                       the directory of the file holding the call
#   embed_tools_cache   the tools' cache (`volec check`, `query`) holds
#                       while an embedded file is the same, and not once
#                       it changes, stops being UTF-8 or goes
#   embed_code_cache    the code cache (a build with --cache=on) rebuilds
#                       what an embedded file's change changes: the output
#                       runs with the new text and is the object a build
#                       without the cache makes, the rest from the cache
#   embed_wgsl_tokens   (0.26.0) an embedded block's text is one token,
#                       `embedded`, between its braces (`volec --tokens`)
#   lower_code_cache    (0.26.1) the code cache's key holds VOLE_LOWER: an
#                       `ast` build's objects never serve a `places` build,
#                       nor the reverse (here as embed_code_cache's sibling)
#
# usage: tests/embed/run.sh [-c COMPILER]
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each; exits 1 if one
# failed. POSIX sh and awk only.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPILER="$ROOT/target/volec"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        *) echo "usage: tests/embed/run.sh [-c COMPILER]" >&2; exit 2 ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "embed/run.sh: no compiler at $COMPILER" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-embed.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
STATUS=0
check() { # <name> <ok> <why>
    if [ "$2" = 1 ]; then
        echo "pass $1"
    else
        echo "FAIL $1:"
        printf '%s\n' "$3" | head -20 | sed 's/^/    /'
        STATUS=1
    fi
}

# embed_crlf
d="$WORK/crlf"
mkdir -p "$d"
printf 'fn main() -> i32 {\r\n    let s = """\r\n        a\r\n          b \\\r\n        c\r\n\r\n        """;\r\n    print(s);\r\n    println("|");\r\n    0\r\n}\r\n' >"$d/main.vl"
out=$(cd "$d" && VOLE_OK=0 "$COMPILER" main.vl -o prog 2>&1 && ./prog | od -An -c | tr -s ' ' | sed 's/ *$//')
ok=0
[ "$out" = ' a \n b c \n | \n' ] && ok=1
check embed_crlf "$ok" "$out"

# embed_message
d="$WORK/msg"
mkdir -p "$d/gfx"
printf 'mod gfx;\n\nfn main() -> i32 {\n    println(gfx::W);\n    0\n}\n' >"$d/main.vl"
printf 'pub const W: [u8] = include_str("shaders/a.wgsl");\n' >"$d/gfx/mod.vl"
out=$(cd "$d" && "$COMPILER" check main.vl 2>&1)
ok=0
printf '%s\n' "$out" | grep -q '^gfx/mod.vl:1:21: error\[embed.missing\] include_str("shaders/a.wgsl"): cannot read gfx/shaders/a.wgsl | help: the path is relative to the directory of gfx/mod.vl, the file that holds the call$' && ok=1
check embed_message "$ok" "$out"

# embed_tools_cache: each `check` traced (hit, miss, save)
d="$WORK/tools"
mkdir -p "$d/data"
printf 'mod data;\n\nfn main() -> i32 {\n    println(data::TEXT);\n    0\n}\n' >"$d/main.vl"
printf 'pub const TEXT: [u8] = include_str("text.txt");\n' >"$d/data/mod.vl"
printf 'one\n' >"$d/data/text.txt"
tools_check() { # <label>: the check's first line and the cache's words, into $d/log
    : >"$d/trace"
    r=$(cd "$d" && VOLE_CACHE="$d/cache" VOLE_CACHE_TRACE="$d/trace" "$COMPILER" check main.vl 2>&1 | head -1)
    echo "$1 $(tr '\n' ' ' <"$d/trace")| $r" >>"$d/log"
}
: >"$d/log"
tools_check same
tools_check again
printf 'two\n' >"$d/data/text.txt"
tools_check changed
printf '\377\n' >"$d/data/text.txt"
tools_check not-utf8
rm "$d/data/text.txt"
tools_check gone
printf 'two\n' >"$d/data/text.txt"
tools_check back
tools_check back-again
want='same miss save | ok: 0 errors in main.vl
again hit | ok: 0 errors in main.vl
changed miss save | ok: 0 errors in main.vl
not-utf8 miss save | data/mod.vl:1:24: error[embed.utf8] include_str("text.txt"): data/text.txt is not UTF-8 (at byte 0) | help: include_str'"'"'s text is a str, UTF-8; include_bytes gives any file'"'"'s bytes, a [u8] | try: volec fix --suggested main.vl
gone miss save | data/mod.vl:1:24: error[embed.missing] include_str("text.txt"): cannot read data/text.txt | help: the path is relative to the directory of data/mod.vl, the file that holds the call
back miss save | ok: 0 errors in main.vl
back-again hit | ok: 0 errors in main.vl'
got=$(sed "s|$COMPILER|volec|g" "$d/log")
ok=0
[ "$got" = "$want" ] && ok=1
check embed_tools_cache "$ok" "$(printf 'expected:\n%s\ngot:\n%s\n' "$want" "$got")"

# embed_code_cache: built with the code cache, the text changed, built
# again: the new text, the object of a build without the cache, and the
# other functions (std's) from the cache
d="$WORK/code"
mkdir -p "$d"
printf 'const MSG: [u8] = include_str("msg.txt");\n\nfn main() -> i32 {\n    println(MSG);\n    0\n}\n' >"$d/main.vl"
printf 'first' >"$d/msg.txt"
code_build() { # <out> <cache: on|no>
    flag=--cache=on
    [ "$2" = on ] || flag=--no-cache
    : >"$d/trace"
    (cd "$d" && VOLE_OK=0 VOLE_CODE_CACHE=on VOLE_CACHE="$d/cache" VOLE_CACHE_SYNC=1 VOLE_CACHE_TRACE="$d/trace" \
        "$COMPILER" -O2 $flag main.vl -c -o "$1.o" && cc "$1.o" -o "$1" -lm && "$1") 2>&1
}
first=$(code_build "$d/a" on)
printf 'second' >"$d/msg.txt"
second=$(code_build "$d/b" on)
hits=$(awk '$1 == "code" { h += $2 } END { print h + 0 }' "$d/trace")
clean=$(code_build "$d/c" no)
ok=0
[ "$first" = first ] && [ "$second" = second ] && [ "$clean" = second ] && cmp -s "$d/b.o" "$d/c.o" \
    && [ "$hits" -gt 0 ] && ok=1
check embed_code_cache "$ok" "first: $first; after the change: $second (hits $hits); clean: $clean; objects $(cmp "$d/b.o" "$d/c.o" 2>&1 || true)"

# embed_wgsl_tokens
d="$WORK/tokens"
mkdir -p "$d"
printf 'embed wgsl K {\n    fn f() -> u32 { return 1u; } // }\n}\n' >"$d/main.vl"
out=$("$COMPILER" --tokens "$d/main.vl" 2>&1)
want=$(printf '0 5 0 ident embed\n6 10 0 ident wgsl\n11 12 0 ident K\n13 14 0 {\n14 53 1 embedded\n53 54 0 }')
check embed_wgsl_tokens "$([ "$(printf '%s\n' "$out" | head -6)" = "$want" ] && echo 1)" "$out"

# lower_code_cache: VOLE_LOWER is in the code cache's key: a build under
# one lowering never takes another's objects (no hit at the first build
# under each), a second build under the same one does, and each object is
# the one its lowering makes without the cache
d="$WORK/lower"
mkdir -p "$d"
printf 'struct P {\n    x: i64,\n    y: i64,\n}\n\nfn sum(p: P) -> i64 {\n    p.x + p.y\n}\n\nfn main() -> i32 {\n    let p = P { x: 2, y: 3 };\n    println(sum(p));\n    0\n}\n' >"$d/main.vl"
lower_build() { # <lowering> <out> <cache: on|no>; prints the run and the code hits
    flag=--cache=on
    [ "$3" = on ] || flag=--no-cache
    : >"$d/trace"
    out=$(cd "$d" && VOLE_OK=0 VOLE_LOWER=$1 VOLE_CODE_CACHE=on VOLE_CACHE="$d/cache" VOLE_CACHE_SYNC=1 \
        VOLE_CACHE_TRACE="$d/trace" "$COMPILER" -O2 $flag main.vl -c -o "$2.o" && cc "$2.o" -o "$2" -lm && "$2" 2>&1)
    echo "$out $(awk '$1 == "code" { h += $2 } END { print h + 0 }' "$d/trace")"
}
a1=$(lower_build ast "$d/a1" on)
p1=$(lower_build places "$d/p1" on)
p2=$(lower_build places "$d/p2" on)
a2=$(lower_build ast "$d/a2" on)
lower_build ast "$d/ac" no >/dev/null
lower_build places "$d/pc" no >/dev/null
ok=0
set -- $a1 $p1 $p2 $a2
[ "$1 $2 $3 $4" = "5 0 5 0" ] && [ "$5" = 5 ] && [ "$6" -gt 0 ] && [ "$7" = 5 ] && [ "$8" -gt 0 ] \
    && cmp -s "$d/a2.o" "$d/ac.o" && cmp -s "$d/p2.o" "$d/pc.o" && ok=1
check lower_code_cache "$ok" "run and code hits: ast $a1, places $p1, places again $p2, ast again $a2; objects: ast $(cmp "$d/a2.o" "$d/ac.o" 2>&1 || true), places $(cmp "$d/p2.o" "$d/pc.o" 2>&1 || true)"

exit $STATUS
