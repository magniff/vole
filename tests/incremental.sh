#!/bin/sh
# (0.18.1) Incremental rebuilds give the bytes a clean build gives
# (docs/optimizer.md, "0.18.1: incremental rebuilds"): a program is
# built with the code cache (cold), then edited one function at a time
# and rebuilt with it (warm), and each object must be the one a build
# without the cache makes of the same tree. The compiler's own source is
# one program (EDITS edits), the examples and bench others (4 each), at
# -O1 and -O2, with -j1 and -j8; the edits are seeded and of four kinds,
# each changing what the cache must notice:
#
#   literal  `let x = N;` in a function becomes N + 1: its code;
#   string   a new `let` of a new string before a statement: every later
#            string's and symbol's id moves;
#   line     a comment line: every later function of the file has its
#            checks' positions (their strings) changed;
#   function a new function at the end of a file: every later function's
#            id moves;
#   check    a new `let` indexing an array before a statement: a new
#            run-time check, every later check's site moves;
#   call     (0.30.1) a call statement made twice: its callee (and
#            theirs) called once more, which the inliner and the loop
#            passes read (RT-CG-3: a function called once waits for its
#            caller);
#   uncall   (0.30.1) a call statement taken out: one call fewer;
#   dead     (0.30.1) a call statement copied into `if false { }`: a
#            call that is there and never reached.
#
# An edit the program does not build with (a call made twice that moves a
# value twice) is taken back and the next one made (`rejected` counts
# them). (0.30.1) Before the series, each pair of tests/incremental/
# (a program in two versions, NAME.vl.txt: `// VARIANTS: X Y`, its `@V@`
# replaced by X, then Y, `-` for nothing) is built one version after the other with one
# cache, both orders, at -O1 and -O2, to assembly and to an object, and
# the second build must be the bytes of a build without the cache: the
# edits of the codegen red team's RT-CG-3, which 0.30.0 failed.
#
# Then the tree is put back and built once more (the first build's
# entries, kept). The compiler's source also takes real edits: recent
# commits to compiler/src (git log) of at most 60 changed lines that
# still apply, each undone (git apply -R), built, and redone. The hits are
# counted ($VOLE_CACHE_TRACE).
#
# usage: tests/incremental.sh [-c COMPILER] [-n EDITS] [-r COMMITS] [-s SEED] [-j JOBS] [FILTER]
#
#   -c COMPILER   the volec to check (default: target/volec)
#   -n EDITS      the compiler's edits (default 10)
#   -r COMMITS    the compiler's real edits, from git (default 6)
#   -s SEED       the edits' seed (default 1)
#   -j JOBS       programs checked at once (default: the number of CPUs,
#                 or the slots of $VOLE_JOBSERVER, see tests/run.sh)
#   FILTER        only the programs whose path contains FILTER

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
EDITS=10
COMMITS=6
SEED=1
JOBS=""
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -n) EDITS=$2; shift 2 ;;
        -r) COMMITS=$2; shift 2 ;;
        -s) SEED=$2; shift 2 ;;
        -j) JOBS=$2; shift 2 ;;
        -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
TARGET=$("$COMPILER" --version | sed 's/.*host: \([a-z0-9_-]*\).*/\1/')
WORK="$ROOT/target/incremental"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$ROOT" || exit 1

# A program's test directives (tests/directives.awk) into directory $2.
case_directives() { # <program> <dir>
    mkdir -p "$2"
    case "$1" in
        examples/*) cd_file=$(grep -l -x "// SOURCE: $1" tests/examples/*.test 2>/dev/null | head -1) ;;
        *) cd_file=$1 ;;
    esac
    [ -n "$cd_file" ] || return 0
    awk -v dir="$2" -v target="$TARGET" -f "$ROOT/tests/directives.awk" "$cd_file"
}

# Edit number $2 (seed $3) of the program in tree $1 (its .vl files);
# prints what it did.
edit() { # <tree> <n> <seed>
    find "$1" -name '*.vl' | sort >"$1.files"
    awk -v n="$2" -v seed="$3" -v list="$1.files" -v tree="$1/" '
        function rnd(m) { state = (state * 1103515245 + 12345) % 2147483648; return int(state / 65536) % m }
        BEGIN {
            state = seed * 7919 + n * 104729
            nf = 0
            nc = 0
            while ((getline f < list) > 0) files[nf++] = f
            kinds[0] = "literal"; kinds[1] = "string"; kinds[2] = "line"; kinds[3] = "function"
            kinds[4] = "check"; kinds[5] = "call"; kinds[6] = "uncall"; kinds[7] = "dead"
            kind = kinds[(n + seed) % 8]
            # the lines an edit of this kind may take, over every file (a
            # literal edit with none is a line edit)
            nl = 0
            nk = 0
            for (i = 0; i < nf; i++) {
                ln = 0
                while ((getline line < files[i]) > 0) {
                    ln++
                    if (line ~ /^ +let [a-z_][a-z_0-9]* = [0-9]+;$/) { lf[nl] = i; ll[nl] = ln; nl++ }
                    if (line ~ /^ +let [a-z_]/) { cf[nc] = i; cl[nc] = ln; nc++ }
                    # (a call statement: `f(..);`, `x.f(..);`, not a `let`,
                    # an `if`, a `return` or a `match` arm)
                    if (line ~ /^ +[a-z_][a-z_0-9:.]*[(].*[)];$/ && line !~ /^ +(let|if|return|while|for|match|else) /) {
                        kf[nk] = i; kl[nk] = ln; nk++
                    }
                }
                close(files[i])
            }
            if (kind == "literal" && nl > 0) {
                nc = nl
                for (i = 0; i < nl; i++) { cf[i] = lf[i]; cl[i] = ll[i] }
            } else if (kind == "literal") {
                kind = "line"
            }
            if (kind == "call" || kind == "uncall" || kind == "dead") {
                if (nk == 0) { kind = "line" } else {
                    nc = nk
                    for (i = 0; i < nk; i++) { cf[i] = kf[i]; cl[i] = kl[i] }
                }
            }
            if (kind == "function") { cf[0] = rnd(nf); cl[0] = -1; nc = 1 }
            if (nc == 0) { print "none"; exit }
            k = rnd(nc)
            file = files[cf[k]]; target = cl[k]
            out = file ".new"
            ln = 0
            while ((getline line < file) > 0) {
                ln++
                if (ln == target) {
                    indent = line; sub(/[^ ].*/, "", indent)
                    if (kind == "literal") {
                        num = line; sub(/.* = /, "", num); sub(/;$/, "", num)
                        sub(/ = [0-9]+;$/, " = " (num + 1) ";", line)
                    } else if (kind == "string") {
                        print indent "let incr_s" n ": [u8] = \"incremental edit " n "\";" > out
                    } else if (kind == "check") {
                        print indent "let incr_a" n ": [i64; 2] = [" n ", 1];" > out
                        print indent "let incr_c" n " = incr_a" n "[" n " % 2];" > out
                    } else if (kind == "call") {
                        print line > out
                    } else if (kind == "uncall") {
                        line = indent "// incremental edit " n ": " substr(line, length(indent) + 1)
                    } else if (kind == "dead") {
                        print indent "if false {" > out
                        print "    " line > out
                        print indent "}" > out
                    } else {
                        print indent "// incremental edit " n > out
                    }
                }
                print line > out
            }
            close(file)
            if (kind == "function") print "\nfn incr_f" n "() -> i64 {\n    " n "\n}" > out
            close(out)
            system("mv \"" out "\" \"" file "\"")
            print kind " " substr(file, length(tree) + 1) (target > 0 ? ":" target : "")
        }' </dev/null
}

# Builds program $2 of tree $1 at -O$3 -j$4 into $5 ($6: with the cache
# or not); its flags from directory $7.
build() { # <tree> <root> <level> <threads> <out> <cache> <directives>
    flags=""
    [ -f "$7/flags" ] && flags=$(sed "s|@ROOT@|$ROOT|g" "$7/flags")
    no=--cache=on
    [ "$6" = yes ] || no=--no-cache
    # shellcheck disable=SC2086
    (cd "$1" && VOLE_CODE_CACHE=on VOLE_CACHE="$1.cache" VOLE_CACHE_SYNC=1 \
        VOLE_CACHE_TRACE="$1.trace" \
        "$COMPILER" --target "$TARGET" "-O$3" "-j$4" $flags $no -c "$2" -o "$5") >"$5.out" 2>&1
}

# One program at one level and thread count: the cold build, the edits,
# the tree put back.
check() { # <program> <level> <threads> <edits> <n>
    w="$WORK/$5"
    dd="$WORK/directives/$(echo "$1" | tr / _)"
    case "$1" in
        compiler/src/main.vl) src=compiler/src; root=src/main.vl ;;
        */main.vl) src=$(dirname "$1"); root=$(basename "$src")/main.vl ;;
        *) src=$1; root=$(basename "$1") ;;
    esac
    mkdir -p "$w/tree"
    cp -R "$src" "$w/tree/"
    cp -R "$w/tree" "$w/orig"
    what="$1 -O$2 -j$3"
    build "$w/tree" "$root" "$2" "$3" "$w/ref.o" no "$dd"
    if [ ! -f "$w/ref.o" ]; then
        echo "skip $what: it does not build ($(head -1 "$w/ref.o.out"))"
        return
    fi
    build "$w/tree" "$root" "$2" "$3" "$w/cold.o" yes "$dd"
    if ! cmp -s "$w/ref.o" "$w/cold.o"; then
        echo "FAIL $what: the cold build with the cache differs from the build without"
        return
    fi
    i=1
    rejected=0
    tries=0
    kinds=""
    while [ "$i" -le "$4" ]; do
        rm -rf "$w/before"
        cp -R "$w/tree" "$w/before"
        e=$(edit "$w/tree" "$((i + 1000 * tries))" "$SEED")
        build "$w/tree" "$root" "$2" "$3" "$w/ref.o" no "$dd"
        if [ ! -f "$w/ref.o" ]; then
            # (an edit the program does not build with: taken back, and
            # another made; 0.30.1)
            rm -rf "$w/tree"
            mv "$w/before" "$w/tree"
            rejected=$((rejected + 1))
            tries=$((tries + 1))
            if [ "$tries" -ge 20 ]; then
                echo "skip $what: 20 edits in a row at $i do not build (the last: $e, $(head -1 "$w/ref.o.out"))"
                return
            fi
            continue
        fi
        tries=0
        kinds="$kinds ${e%% *}"
        build "$w/tree" "$root" "$2" "$3" "$w/warm.o" yes "$dd"
        if ! cmp -s "$w/ref.o" "$w/warm.o"; then
            echo "FAIL $what: after edit $i ($e) the rebuild differs from a clean build; kept in $w"
            return
        fi
        i=$((i + 1))
    done
    rm -rf "$w/tree"
    mv "$w/orig" "$w/tree"
    build "$w/tree" "$root" "$2" "$3" "$w/ref.o" no "$dd"
    build "$w/tree" "$root" "$2" "$3" "$w/warm.o" yes "$dd"
    if ! cmp -s "$w/ref.o" "$w/warm.o"; then
        echo "FAIL $what: the tree put back rebuilds differently; kept in $w"
        return
    fi
    real=0
    if [ "$1" = compiler/src/main.vl ]; then
        for c in $(cat "$WORK/commits" 2>/dev/null); do
            git -C "$ROOT" show "$c" -- compiler/src >"$w/$c.diff"
            (cd "$w/tree" && git apply -R -p2 "$w/$c.diff") 2>/dev/null || continue
            build "$w/tree" "$root" "$2" "$3" "$w/ref.o" no "$dd"
            build "$w/tree" "$root" "$2" "$3" "$w/warm.o" yes "$dd"
            if [ ! -f "$w/ref.o" ] || ! cmp -s "$w/ref.o" "$w/warm.o"; then
                echo "FAIL $what: with commit $c undone the rebuild differs from a clean build; kept in $w"
                return
            fi
            (cd "$w/tree" && git apply -p2 "$w/$c.diff")
            real=$((real + 1))
        done
    fi
    hits=$(awk '$1 == "code" { h += $2; m += $3 } END { print h + 0, m + 0 }' "$w/tree.trace")
    rm -rf "$w"
    echo "ok $what: $4 edits ($(echo $kinds | tr ' ' ,); $rejected rejected), $real commits undone $hits"
}

# (0.30.1) The pairs: each version built after the other with one cache
# must be the bytes of the version built without it.
pairs_ok=0
pairs_failed=0
for p in tests/incremental/*.vl.txt; do
    [ -f "$p" ] || continue
    case "$p" in *"$FILTER"*) ;; *) continue ;; esac
    pw="$WORK/pair"
    set -- $(sed -n 's|^// VARIANTS: *||p' "$p" | head -1)
    [ $# -eq 2 ] || { echo "FAIL $p: no '// VARIANTS: X Y' line"; pairs_failed=$((pairs_failed + 1)); continue; }
    va=$1
    vb=$2
    for order in ab ba; do
        if [ $order = ab ]; then first=$va; second=$vb; else first=$vb; second=$va; fi
        for opt in 1 2; do
            for mode in -S -c; do
                rm -rf "$pw"
                mkdir -p "$pw"
                f1=$first; [ "$f1" = - ] && f1=""
                f2=$second; [ "$f2" = - ] && f2=""
                sed "s|@V@|$f1|" "$p" >"$pw/main.vl"
                (cd "$pw" && VOLE_CODE_CACHE=on VOLE_CACHE="$pw/cache" VOLE_CACHE_SYNC=1 \
                    "$COMPILER" --target "$TARGET" "-O$opt" --cache=on $mode main.vl -o first.out) >"$pw/log" 2>&1
                sed "s|@V@|$f2|" "$p" >"$pw/main.vl"
                (cd "$pw" && VOLE_CODE_CACHE=on VOLE_CACHE="$pw/cache" VOLE_CACHE_SYNC=1 \
                    "$COMPILER" --target "$TARGET" "-O$opt" --cache=on $mode main.vl -o warm.out) >>"$pw/log" 2>&1
                (cd "$pw" && VOLE_CACHE=off "$COMPILER" --target "$TARGET" "-O$opt" --no-cache $mode main.vl -o cold.out) >>"$pw/log" 2>&1
                if [ -f "$pw/cold.out" ] && cmp -s "$pw/warm.out" "$pw/cold.out"; then
                    pairs_ok=$((pairs_ok + 1))
                else
                    echo "FAIL $p: '$first' then '$second' at -O$opt $mode: the warm build differs from a build without the cache"
                    pairs_failed=$((pairs_failed + 1))
                fi
            done
        done
    done
done
rm -rf "$WORK/pair"
[ $((pairs_ok + pairs_failed)) -eq 0 ] \
    || echo "incremental pairs: $pairs_ok of $((pairs_ok + pairs_failed)) warm builds the same as clean builds"

list="$WORK/list"
: >"$list"
for f in compiler/src/main.vl examples/*/main.vl bench/*.vl; do
    [ -f "$f" ] || continue
    case "$f" in *"$FILTER"*) ;; *) continue ;; esac
    grep -q '// CSOURCE\|// CHEADER' "$f" && continue
    case "$f" in
        examples/*) grep -l -x "// SOURCE: $f" tests/examples/*.test 2>/dev/null \
            | xargs grep -q '^// CSOURCE' 2>/dev/null && continue ;;
    esac
    case_directives "$f" "$WORK/directives/$(echo "$f" | tr / _)"
    echo "$f" >>"$list"
done
# Recent commits to compiler/src of at most 60 changed lines, which undo
# on the tree as it is (the compiler's real edits).
if [ "$COMMITS" -gt 0 ] && git -C "$ROOT" rev-parse >/dev/null 2>&1; then
    : >"$WORK/commits"
    for c in $(git -C "$ROOT" log --no-merges --format=%h -n 80 -- compiler/src); do
        lines=$(git -C "$ROOT" show --numstat --format= "$c" -- compiler/src | awk '{ n += $1 + $2 } END { print n + 0 }')
        [ "$lines" -gt 0 ] && [ "$lines" -le 60 ] || continue
        git -C "$ROOT" show "$c" -- compiler/src | git -C "$ROOT" apply -R --check 2>/dev/null || continue
        echo "$c" >>"$WORK/commits"
        [ "$(wc -l <"$WORK/commits")" -ge "$COMMITS" ] && break
    done
fi
# The slots (as tests/threads.sh).
if [ -z "$JOBS" ] && [ -n "${VOLE_JOBSERVER:-}" ] && [ -p "$VOLE_JOBSERVER" ]; then
    exec 3<>"$VOLE_JOBSERVER"
else
    [ -n "$JOBS" ] || JOBS=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
    rm -f "$WORK/slots"
    mkfifo "$WORK/slots"
    exec 3<>"$WORK/slots"
    i=0
    while [ "$i" -lt "$JOBS" ]; do
        echo >&3
        i=$((i + 1))
    done
fi
n=0
run() { # <program> <level> <threads> <edits>
    n=$((n + 1))
    read -r _ <&3
    ( trap 'echo >&3' EXIT; trap 'exit 1' HUP INT TERM; check "$1" "$2" "$3" "$4" "$n" >"$WORK/$n.result" ) &
}
while read -r f; do
    edits=4
    [ "$f" = compiler/src/main.vl ] && edits=$EDITS
    for o in 1 2; do
        for j in 1 8; do
            run "$f" "$o" "$j" "$edits"
        done
    done
done <"$list"
wait
exec 3>&-
i=1
ok=0
failed=0
skipped=0
while [ "$i" -le "$n" ]; do
    if grep -q '^ok' "$WORK/$i.result"; then
        ok=$((ok + 1))
        case "$(cat "$WORK/$i.result")" in "ok compiler/"*) cat "$WORK/$i.result" ;; esac
    elif grep -q '^skip' "$WORK/$i.result"; then
        skipped=$((skipped + 1))
        cat "$WORK/$i.result"
    else
        failed=$((failed + 1))
        cat "$WORK/$i.result"
    fi
    i=$((i + 1))
done
hits=$(cat "$WORK"/*.result 2>/dev/null | awk '$1 == "ok" { h += $(NF - 1); m += $NF } END { if (h + m > 0) printf "%d%%", 100 * h / (h + m); else print "-" }')
echo "incremental: $ok of $n edit series rebuilt the same as clean builds ($TARGET, hits $hits)$([ $skipped -eq 0 ] || echo ", $skipped skipped")$([ $failed -eq 0 ] || echo ", $failed differ")"
# (a run of the whole tree that checked no pair checked nothing: a FAIL)
[ $failed -eq 0 ] && [ $pairs_failed -eq 0 ] && { [ -n "$FILTER" ] || [ $pairs_ok -gt 0 ]; }
