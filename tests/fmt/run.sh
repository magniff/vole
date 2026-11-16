#!/bin/sh
# The test of `volec fmt` (0.13): the tree is formatted, and formatting
# changes no program's meaning. POSIX sh and awk only.
#
# usage: tests/fmt/run.sh [-c COMPILER] [-j JOBS] [-l] [-n NAME] [FILTER...]
#
#   -j JOBS     programs of `compiles` compiled at once (default 2)
#   -l          (0.30) list the checks that would run, `check NAME`, and
#               run nothing
#   -n NAME     (0.30) only the check named NAME exactly (repeatable)
#   FILTER...   (0.30) only the checks below whose name contains a FILTER
#               (`tests/fmt/run.sh tree embed`: the seconds' ones, not the
#               minutes of roundtrip, compiles and same-output); several,
#               and -n, select the union. Selecting nothing is an error
#               (`no case matches`), not a pass.
#
# The first line is the plan (`fmt: N checks: NAMES`); each check's result
# is printed as it ends.
#
#   tree        `volec fmt --all --check` from the root: every .vl of
#               compiler/, tests/, examples/ and bench/ is formatted (but
#               the ones fmt leaves as they are: not lexed, unbalanced
#               brackets, conflict markers, generated; and the programs of
#               the tools' transcript tests, tests/query/ and
#               tests/refactor/, whose text is what they test)
#   roundtrip   a copy of those directories with every line's
#               indentation removed (but a string's continuation lines
#               and, 0.25.3, a text block's; 0.26.0, an embedded
#               block's, `embed wgsl K {` to its `}`),
#               formatted: compiler/src and compiler/std come back byte
#               for byte (the fixpoint), and so does every file of the
#               rest that has no block comment
#   compiles    every program of the corpus (tests/run, examples, bench,
#               compiler/src) compiled at -O2 from the tree and from the
#               copy: the same assembly, exit status and messages (their
#               positions and the compiler's path aside); (0.30) only
#               the programs with a file the round trip did not bring
#               back byte for byte (the others are the same text); (0.25.5) a
#               program a file of which changed after the copy was made
#               is said so (`changed during the run: rerun`), not `differ`
#   embed_block (0.26.0) an embedded block's bytes, kept by fmt as they
#               are, the vole around it formatted
#   embed_with  (0.26.2) a block's `with` header kept on its one line
#   unreadable_at (0.30.1) a file fmt leaves as it is, not lexed, is named
#               with the line of the lexer's error: a byte that is not
#               UTF-8 on line 3 (lex.utf8, before any token: it was line
#               1), an unterminated string on line 4
#   same-output the compiler built from the copy's compiler/src: the same
#               object as the one built from the tree's, and `same-output`
#               against it: identical
#
# Prints `pass NAME` or `FAIL NAME` (and why) for each; exits 1 if one
# failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
. "$ROOT/tests/jobs.sh"
COMPILER="$ROOT/target/volec"
JOBS=2
LIST=0
FILTERS=
USAGE="usage: tests/fmt/run.sh [-c COMPILER] [-j JOBS] [-l] [-n NAME] [FILTER...]"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; COMPILER=$2; shift 2 ;;
        -j) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; JOBS=$2; shift 2 ;;
        -l) LIST=1; shift ;;
        -n) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
            FILTERS="$FILTERS=$2
"
            shift 2 ;;
        -h|--help) sed -n '2,/^# Prints /p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        -*) echo "tests/fmt/run.sh: unknown option '$1'" >&2; echo "$USAGE" >&2; exit 2 ;;
        *) FILTERS="$FILTERS$1
"
            shift ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-fmt.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
# The checks, then the ones selected.
for c in tree embed_block embed_with unreadable_at roundtrip compiles same-output; do
    echo "check $c"
done | jobs_select "$FILTERS" >"$WORK/sel"
if [ ! -s "$WORK/sel" ]; then
    echo "tests/fmt/run.sh: no case matches $(jobs_filters_text "$FILTERS") (tests/fmt/run.sh -l lists the checks)" >&2
    exit 2
fi
if [ $LIST -eq 1 ]; then
    cat "$WORK/sel"
    exit 0
fi
[ -x "$COMPILER" ] || { echo "fmt/run.sh: no compiler at $COMPILER" >&2; exit 2; }
echo "fmt: $(wc -l <"$WORK/sel" | tr -d ' ') checks: $(cut -d' ' -f2 "$WORK/sel" | tr '\n' ' ' | sed 's/ $//')"
# Whether check $1 is selected.
sel() {
    grep -q -x -F -- "check $1" "$WORK/sel"
}
STATUS=0
check() { # <name> <ok> <why> [what passed]
    if [ "$2" = 1 ]; then
        echo "pass $1${4:+ ($4)}"
    else
        echo "FAIL $1:"
        printf '%s\n' "$3" | head -20 | sed 's/^/    /'
        STATUS=1
    fi
}
cd "$ROOT" || exit 2

# tree
if sel tree; then
    "$COMPILER" fmt --all --check >"$WORK/check.out" 2>&1
    bad=$(grep '\.vl$' "$WORK/check.out" | grep -v '^try: ')
    check tree "$([ -z "$bad" ] && echo 1)" "$bad"
fi

# embed_block (0.26.0): an embedded block's bytes are kept as they are
# (its odd indentation, a `}` in a comment, blank lines), the vole around
# it formatted
if sel embed_block || sel embed_with; then
    mkdir -p "$WORK/embed"
fi
if sel embed_block; then
    printf 'embed wgsl K {\n  @compute   @workgroup_size(1)\n\tfn main() {  // }\n\n      let x=1u;\n  }\n}\nfn  f( ) -> i32 { 1 }\n' >"$WORK/embed/main.vl"
    "$COMPILER" fmt "$WORK/embed/main.vl" >"$WORK/embed/out" 2>&1
    printf 'embed wgsl K {\n  @compute   @workgroup_size(1)\n\tfn main() {  // }\n\n      let x=1u;\n  }\n}\nfn f() -> i32 { 1 }\n' >"$WORK/embed/want"
    check embed_block "$(cmp -s "$WORK/embed/main.vl" "$WORK/embed/want" && echo 1)" \
        "$(cat "$WORK/embed/out"; diff "$WORK/embed/want" "$WORK/embed/main.vl")"
fi

# embed_with (0.26.2): a block with parts keeps its header, `with` list
# and all, on one line as it is; the file form's is laid out as vole
if sel embed_with; then
    printf 'embed wgsl K with A,  b::B {\n  fn f() {}\n}\nembed  wgsl F with A from "x.wgsl"  ;\n' >"$WORK/embed/with.vl"
    "$COMPILER" fmt "$WORK/embed/with.vl" >"$WORK/embed/out" 2>&1
    printf 'embed wgsl K with A,  b::B {\n  fn f() {}\n}\nembed wgsl F with A from "x.wgsl";\n' >"$WORK/embed/want"
    check embed_with "$(cmp -s "$WORK/embed/with.vl" "$WORK/embed/want" && echo 1)" \
        "$(cat "$WORK/embed/out"; diff "$WORK/embed/want" "$WORK/embed/with.vl")"
fi

# unreadable_at (0.30.1): the line of the error, not of the last token
if sel unreadable_at; then
    mkdir -p "$WORK/unread"
    printf 'fn main() {\n    // ok\n    let s = "a\303x";\n}\n' >"$WORK/unread/utf8.vl"
    printf 'fn main() {\n    let a = 1;\n\n    let s = "open;\n}\n' >"$WORK/unread/open.vl"
    "$COMPILER" fmt --check "$WORK/unread/utf8.vl" >"$WORK/unread/o1" 2>&1
    "$COMPILER" fmt --check "$WORK/unread/open.vl" >"$WORK/unread/o2" 2>&1
    check unreadable_at "$(grep -q 'utf8.vl:3: the source is not UTF-8' "$WORK/unread/o1" \
        && grep -q 'open.vl:4: ' "$WORK/unread/o2" && echo 1)" \
        "$(cat "$WORK/unread/o1" "$WORK/unread/o2")"
fi

# roundtrip (the copy: for compiles and same-output too)
if sel roundtrip || sel compiles || sel same-output; then
    COPY="$WORK/copy"
    mkdir -p "$COPY"
    # (0.25.5: a file changed after this is changed during the run: compiles
    # says so, not `differ`)
    : >"$WORK/copied"
    cp -R compiler tests examples bench "$COPY/"
    find compiler/src tests examples bench -name .volec -prune -o -name '*.vl' -print \
        | grep -v '^tests/query/' | grep -v '^tests/refactor/' | sort >"$WORK/files"
    # (0.30: one awk for every file, not one per file: 6000 processes were
    # most of roundtrip's three minutes in a loaded suite)
    # (a generated file, `// Generated by` on its first line, is left as it
    # was copied)
    # (0.25.3: a text block's lines, its closing line included, as they
    # are: their indentation is part of the value)
    # (a raw block's closing """ has as many #s as its r, kept in h)
    # (0.26.0: an embedded block's lines, `embed wgsl K {` to its `}`, as
    # they are: fmt keeps them; d counts its braces outside `//` comments)
    awk -v copy="$COPY" 'function braces(l,  t) { t = l; sub(/\/\/.*/, "", t); return gsub(/\{/, "{", t) - gsub(/\}/, "}", t) }
        function dedent(f,  out, first, ine, inb, cont, d, h) {
            out = copy "/" f
            first = 1; ine = 0; inb = 0; cont = 0; d = 0; h = ""
            while ((getline < f) > 0) {
                if (first) { first = 0; if ($0 ~ /^\/\/ Generated by/) break }
                if (ine) { print > out; d += braces($0); if (d <= 0) ine = 0; continue }
                if ($0 ~ /^[ \t]*(pub[ \t]+)?embed[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+[A-Za-z_][A-Za-z0-9_]*([ \t]+with[ \t]+[A-Za-z0-9_:, \t]+)?[ \t]*\{/ && !inb && !cont) {
                    print > out; d = braces($0); if (d > 0) ine = 1; continue }
                if (inb) { print > out; if (match($0, /^[ \t]*"""/) && substr($0, RSTART + RLENGTH, length(h)) == h) inb = 0; continue }
                if (!cont) sub(/^[ \t]+/, ""); print > out; cont = /\\$/
                if ($0 ~ /(^|[^"])"""[ \t]*\r?$/) { inb = 1; h = ""; if (match($0, /#+"""[ \t]*\r?$/)) { h = substr($0, RSTART, RLENGTH); sub(/".*/, "", h) } }
            }
            close(f)
            if (!first) close(out)
        }
        { dedent($0) }' "$WORK/files"
    (cd "$COPY" && "$COMPILER" fmt --all) >"$WORK/fmt.out" 2>&1
    # (0.30) The files of the list the round trip did not bring back byte
    # for byte (one diff of the trees, not a cmp per file):
    # $WORK/changed. A file changed in the tree after the copy is in it too.
    for d in compiler/src tests examples bench; do
        diff -rq "$d" "$COPY/$d" 2>/dev/null
    done | awk -v copy="$COPY" 'substr($0, 1, 6) == "Files " && / differ$/ {
            s = substr($0, 7); i = index(s, " and " copy "/"); if (i) print substr(s, 1, i - 1) }' \
        | grep -x -F -f "$WORK/files" >"$WORK/changed"
    # (and the diff is checked: every 40th file it says is the same, cmp'd)
    grep -v -x -F -f "$WORK/changed" "$WORK/files" | awk 'NR % 40 == 1' | while IFS= read -r f; do
        cmp -s "$f" "$COPY/$f" || echo "$f"
    done >"$WORK/missed"
fi
if sel roundtrip; then
    # (a file fmt leaves as it is, not lexed or unbalanced, stays dedented)
    : >"$WORK/differs"
    while IFS= read -r f; do
        "$COMPILER" fmt "$f" --check 2>&1 | grep -q '^error fmt.unreadable' && continue
        case "$f" in
            compiler/*) echo "$f" >>"$WORK/differs" ;;
            *) grep -q '/\*' "$f" || echo "$f" >>"$WORK/differs" ;;
        esac
    done <"$WORK/changed"
    n=$(wc -l <"$WORK/differs" | tr -d ' ')
    check roundtrip "$([ "$n" = 0 ] && echo 1)" \
        "$n files differ after a round trip: $(head -5 "$WORK/differs" | tr '\n' ' ')
    $(cat "$WORK/fmt.out")"
fi

# compiles
if sel compiles; then
    # (examples/tools/ has its own runner, and programs that do not compile)
    programs=$(ls tests/run/*.vl tests/run/*/main.vl examples/*/main.vl examples/*/*/main.vl bench/*.vl 2>/dev/null | grep -v '^examples/tools/')
    mkdir -p "$WORK/c"
    printf '%s\n' $programs compiler/src/main.vl | awk -v w="$WORK/c" '{ print NR " " $0 }' >"$WORK/list"
    # (0.25.5) The first of program $1's files (its directory's, for a
    # program of several; compiler/src and compiler/std for the compiler)
    # changed after the copy was made, or nothing.
    changed_since_copy() {
        case "$1" in
            compiler/src/main.vl) where="compiler/src compiler/std" ;;
            tests/run/*/main.vl|examples/*/main.vl|examples/*/*/main.vl) where=$(dirname "$1") ;;
            *) where=$1 ;;
        esac
        # shellcheck disable=SC2086
        (cd "$ROOT" && find $where -name '*.vl' -newer "$WORK/copied" 2>/dev/null | head -1)
    }
    compile_one() { # <n> <program>
        d="$WORK/c/$1"
        mkdir -p "$d"
        # (0.18.1: without the success line, which names the output)
        VOLE_OK=0 "$COMPILER" --diagnostics=human -O2 -S "$ROOT/$2" -o "$d/a.s" >"$d/a.out" 2>&1
        echo $? >"$d/a.rc"
        VOLE_OK=0 "$COMPILER" --diagnostics=human -O2 -S "$COPY/$2" -o "$d/b.s" >"$d/b.out" 2>&1
        echo $? >"$d/b.rc"
        # (0.17: try: lines start with the compiler as it was run, and name
        # positions as FILE:LINE and `the arm at line N`; 0.25: a closure's type
        # in a note names its file, cut to a length that depends on the path; a
        # compile that failed may leave part of an assembly file, not compared)
        sed -e "s|$COMPILER|volec|g" -e "s|$ROOT/||g" -e 's|line [0-9]*, column [0-9]*|POS|g' \
            -e 's|\.vl:[0-9][0-9]*|.vl:N|g' -e 's|at line [0-9]*|at line N|g' \
            -e "s|closure([^']*'|closure'|g" "$d/a.out" >"$d/a.msg"
        sed -e "s|$COMPILER|volec|g" -e "s|$COPY/||g" -e 's|line [0-9]*, column [0-9]*|POS|g' \
            -e 's|\.vl:[0-9][0-9]*|.vl:N|g' -e 's|at line [0-9]*|at line N|g' \
            -e "s|closure([^']*'|closure'|g" "$d/b.out" >"$d/b.msg"
        # (0.18: the run-time checks' messages and sites hold positions and the
        # conditions' text: from rt.messages to the next label that is not the
        # helper's, left out)
        for s in a b; do
            [ -f "$d/$s.s" ] && awk '/rt\.messages:$/ { skip = 1; next }
                skip && /^[^ \t].*:$/ && !/rt\./ { skip = 0 } !skip' "$d/$s.s" >"$d/$s.t" && mv "$d/$s.t" "$d/$s.s"
        done
        if cmp -s "$d/a.rc" "$d/b.rc" && cmp -s "$d/a.msg" "$d/b.msg" \
            && { [ ! -f "$d/a.s" ] || [ "$(cat "$d/a.rc")" != 0 ] || cmp -s "$d/a.s" "$d/b.s"; }; then
            echo same >"$d/result"
        elif ch=$(changed_since_copy "$2") && [ -n "$ch" ]; then
            # (0.25.5) a file of the program changed after the copy was made
            # (an agent's edit while the suite ran): the two compiles read
            # different text, which says nothing of fmt (opt254 #6)
            echo "changed $2 $ch" >"$d/result"
        else
            echo "$2" >"$d/result"
        fi
        rm -f "$d/a.s" "$d/b.s"
    }
    # (0.30) Whether a file of program $1 is in $WORK/changed (the round
    # trip did not bring it back byte for byte): the others are the same
    # text from the copy as from the tree, and compiling the same text
    # twice says nothing of fmt, so they are not compiled (they were
    # 5000 of the corpus's 5300, two compiles each, most of the suite's
    # fifteen minutes). Its files as changed_since_copy reads them.
    fmt_touched() {
        case "$1" in
            compiler/src/main.vl) grep -q -e '^compiler/src/' -e '^compiler/std/' "$WORK/changed" ;;
            tests/run/*/main.vl|examples/*/main.vl|examples/*/*/main.vl) grep -q -F "$(dirname "$1")/" "$WORK/changed" ;;
            *) grep -q -x -F "$1" "$WORK/changed" ;;
        esac
    }
    i=0
    nsame=0
    while read -r k p; do
        if ! fmt_touched "$p"; then
            mkdir -p "$WORK/c/$k"
            echo same >"$WORK/c/$k/result"
            nsame=$((nsame + 1))
            continue
        fi
        compile_one "$k" "$p" &
        i=$((i + 1))
        [ $((i % JOBS)) = 0 ] && wait
    done <"$WORK/list"
    wait
    total=$(wc -l <"$WORK/list" | tr -d ' ')
    bad=$(cat "$WORK"/c/*/result | grep -v '^same$' | grep -v '^changed ')
    changed=$(cat "$WORK"/c/*/result | awk '$1 == "changed" { printf "%s%s (%s)", sep, $2, $3; sep = ", " }')
    [ -s "$WORK/missed" ] && bad="${bad:+$bad }the tree's diff missed $(head -3 "$WORK/missed" | tr '\n' ' ')"
    check compiles "$([ -z "$bad" ] && [ -z "$changed" ] && [ "$(cat "$WORK"/c/*/result | wc -l | tr -d ' ')" = "$total" ] && echo 1)" \
        "$total programs; differ: ${bad:-none}$([ -n "$changed" ] && printf '; changed during the run, not compared (rerun): %s' "$changed")" \
        "$i of $total programs with a file the round trip changed, compiled both ways; $nsame the same text"
fi

# same-output
if sel same-output; then
    ok=0
    "$COMPILER" compiler/src/main.vl -c -o "$WORK/old.o" >/dev/null 2>&1
    (cd "$COPY" && "$COMPILER" compiler/src/main.vl -c -o "$WORK/new.o") >/dev/null 2>&1
    ${CC:-cc} -o "$WORK/new-volec" "$WORK/new.o" -lm 2>/dev/null
    out=$("$WORK/new-volec" same-output "$COMPILER" --corpus examples --work "$WORK/so" 2>&1)
    cmp -s "$WORK/old.o" "$WORK/new.o" && printf '%s\n' "$out" | grep -q '^identical' && ok=1
    check same-output "$ok" "$out"
fi
exit $STATUS
