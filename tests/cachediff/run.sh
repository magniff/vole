#!/bin/sh
# The tools' cache answers as the front end does (0.25.3): every command
# line of the tools' transcripts (tests/query/*.q, tests/refactor/*.t)
# and of the walkthroughs (examples/GROUP/NAME/README.md's sessions, as
# tests/walkthrough/run.sh runs them) run on the same state of its
# program, at the same path:
#
#   off      VOLE_CACHE=off: the program read in full;
#   cold     with a fresh cache directory: read in full, the cache written;
#   warm     with that directory again: answered from the cache where the
#            command uses it;
#   checked  (a query) from the cache `volec check` made of its program,
#            which records more than a query's;
#   primed   (an edit, when warm did not use the cache: its cold run
#            cached the program it wrote, not the one it read) from the
#            cache `volec check` made of the program as it is;
#   seq      (a refactoring or walkthrough line) with one cache for the
#            whole transcript, as a session has one: what the lines
#            before made, an edit's q-KEY.next.bin.
#
# Each run's output (stdout, stderr), exit status and, but for a query,
# the program's files after it (its journal in .git/vole-edits too) must
# be off's; and when the cold run wrote the cache, a query's warm run must
# have read it. With VOLE_CACHE_TRACE set (the trace: `hit`, `miss`,
# `save`) the cache is written before the command ends, not by its forked
# writer, so the next run always finds it. The state a line runs on is
# what the lines before it left without the cache (`%` lines, shell
# commands, run once, without it). POSIX sh and awk only.
#
# usage: tests/cachediff/run.sh [-c COMPILER] [-j JOBS] [--sample] [NAME...]
#
#   -c COMPILER   the volec binary (default: target/volec)
#   -j JOBS       transcripts at once (default 4)
#   --sample      the default suite's share: the transcripts listed in
#                 tests/cachediff/sample (the whole run is the gate's)
#   NAME          only these transcripts (NAME.q, NAME.t, a walkthrough's
#                 NAME)
#
# Then `volec` run from $PATH must use the cache (volec_in_path).
#
# Prints `pass cachediff/NAME (N lines, H from the cache)` or `FAIL
# cachediff/NAME` (each line that differed, and how) per transcript, then
# a `cachediff:` line with the counts; exits 1 if one failed.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

# One transcript (the workers below): $1 the file, in $CD_WORK.
if [ "${1:-}" = --one ]; then
    file=$2
    case "$file" in
        *.q) kind=q; name=$(basename "$file" .q) ;;
        */README.md) kind=w; name=$(basename "$(dirname "$file")") ;;
        *) kind=t; name=$(basename "$file" .t) ;;
    esac
    label=$name.$kind
    [ $kind = w ] && label=walkthrough:$name
    W="$CD_WORK/$kind-$name"
    mkdir -p "$W"
    W=$(cd "$W" && pwd -P)
    P="$W/p"
    S="$W/state"
    RES="$CD_WORK/res/$kind-$name"
    : >"$W/fails"
    lines=0
    hits=0
    T="$ROOT/tests/refactor"
    export T
    unset VOLE_ROOT VOLE_CACHE VOLE_CACHE_TRACE
    if [ $kind = q ]; then
        QDIR="$ROOT/tests/query"
        [ -d "$QDIR/$name" ] && { VOLE_ROOT="$name/main.vl"; export VOLE_ROOT; }
    elif [ $kind = w ]; then
        # (as tests/walkthrough/run.sh runs them: the compiler as `volec`,
        # an empty HOME, git with no configuration but a name and a date;
        # each `$` command, with its `>` lines, a script)
        mkdir -p "$W/bin" "$W/home" "$S"
        ln -s "$COMPILER" "$W/bin/volec"
        PATH="$W/bin:$PATH"
        HOME="$W/home"
        XDG_CONFIG_HOME="$W/home"
        GIT_CONFIG_NOSYSTEM=1
        GIT_AUTHOR_NAME=you
        GIT_AUTHOR_EMAIL=you@example.com
        GIT_COMMITTER_NAME=you
        GIT_COMMITTER_EMAIL=you@example.com
        GIT_AUTHOR_DATE='2026-01-01T00:00:00Z'
        GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
        export PATH HOME XDG_CONFIG_HOME GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL \
            GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_DATE
        cp -R "$(dirname "$file")/." "$S/"
        (cd "$S" && git init -q . && git symbolic-ref HEAD refs/heads/main && git add -A \
            && git commit -q -m start) >/dev/null 2>&1
        awk -v out="$W" '
            function flush() { if (cmd != "") { printf "%s", cmd > (out "/cmd." n); close(out "/cmd." n); cmd = "" } }
            /^```console[ \t]*$/ && !in_block { in_block = 1; cont = 0; next }
            in_block && /^```[ \t]*$/ { flush(); in_block = 0; next }
            !in_block { next }
            /^\$ / { flush(); n++; cmd = substr($0, 3) "\n"; cont = 1; next }
            cont && /^>( |$)/ { cmd = cmd substr($0, 3) "\n"; next }
            { cont = 0 }
            END { flush(); for (i = 1; i <= n; i++) print "! " i > (out "/lines") }
        ' "$file"
    else
        mkdir -p "$S"
        [ -d "$T/$name" ] && cp -R "$T/$name/." "$S/"
        case "$name" in
            plain*) ;;
            *) (cd "$S" && git init -q . && git -c user.name=t -c user.email=t@t add -A \
                && git -c user.name=t -c user.email=t@t commit -q -m fixture) >/dev/null 2>&1 ;;
        esac
    fi
    # One run of line $1 ($ or % and its ARGS) in mode $2, its output and
    # status in $W/$2.out, .err, .rc; for a .t, the program after it in
    # $W/$2.tree.
    run() {
        rline=$1
        mode=$2
        args=${rline#? }
        rm -rf "$W/$mode.tree" "$W/$mode.trace"
        case $mode in
            off) env_cache=off ;;
            seq) env_cache="$W/seqcache" ;;
            *) env_cache="$W/cache" ;;
        esac
        : >"$W/$mode.trace"
        if [ $kind = q ]; then
            (
                cd "$QDIR" || exit 1
                eval "set -- $args"
                if [ $mode = off ]; then
                    VOLE_CACHE=off "$COMPILER" query "$@"
                else
                    VOLE_CACHE="$env_cache" VOLE_CACHE_TRACE="$W/$mode.trace" "$COMPILER" query "$@"
                fi
            ) >"$W/$mode.out" 2>"$W/$mode.err" </dev/null
            echo $? >"$W/$mode.rc"
            return
        fi
        rm -rf "$P"
        cp -Rp "$S" "$P"
        (
            cd "$P" || exit 1
            if [ $mode != off ]; then
                VOLE_CACHE_TRACE="$W/$mode.trace"
                export VOLE_CACHE_TRACE
            fi
            VOLE_CACHE=$env_cache
            export VOLE_CACHE
            case "$rline" in
                \$*) eval "\"\$COMPILER\" $args" ;;
                !*) sh "$W/cmd.$args" ;;
                *) eval "$args" ;;
            esac
        ) >"$W/$mode.out" 2>"$W/$mode.err" </dev/null
        echo $? >"$W/$mode.rc"
        mv "$P" "$W/$mode.tree"
    }
    # Whether mode $1's run is mode off's: its differences on $W/why.
    same_as_off() {
        : >"$W/why"
        cmp -s "$W/off.rc" "$W/$1.rc" \
            || echo "exit $(cat "$W/off.rc") without the cache, $(cat "$W/$1.rc") $1" >>"$W/why"
        for s in out err; do
            cmp -s "$W/off.$s" "$W/$1.$s" || {
                echo "std$s differs (< off, > $1):"
                diff "$W/off.$s" "$W/$1.$s" | head -12
            } >>"$W/why"
        done
        if [ $kind != q ]; then
            diff -r -x .git "$W/off.tree" "$W/$1.tree" >"$W/tdiff" 2>&1 || {
                echo "the files differ (< off, > $1):"
                head -12 "$W/tdiff"
            } >>"$W/why"
            if [ -d "$W/off.tree/.git/vole-edits" ] || [ -d "$W/$1.tree/.git/vole-edits" ]; then
                diff -r "$W/off.tree/.git/vole-edits" "$W/$1.tree/.git/vole-edits" >"$W/tdiff" 2>&1 || {
                    echo "the journal differs (< off, > $1):"
                    head -12 "$W/tdiff"
                } >>"$W/why"
            fi
        fi
        [ ! -s "$W/why" ]
    }
    case $kind in
        q) grep -E '^\$ ' "$file" >"$W/lines" ;;
        t) grep -E '^[$%] ' "$file" >"$W/lines" ;;
        w) [ -f "$W/lines" ] || : >"$W/lines" ;;
    esac
    n=0
    while IFS= read -r line; do
        n=$((n + 1))
        case "$line" in
            %*)
                run "$line" off
                rm -rf "$S"
                mv "$W/off.tree" "$S"
                continue
                ;;
        esac
        lines=$((lines + 1))
        rm -rf "$W/cache"
        run "$line" off
        run "$line" cold
        run "$line" warm
        bad=""
        same_as_off cold || bad="$bad$(cat "$W/why")
"
        same_as_off warm || bad="$bad$(cat "$W/why")
"
        if [ $kind != q ]; then
            # (and with one cache for the whole transcript, as a session
            # has: what the lines before made of their programs, and an
            # edit's cache of the program it wrote, q-KEY.next.bin)
            run "$line" seq
            same_as_off seq || bad="$bad$(cat "$W/why")
"
            rm -rf "$W/seq.tree"
        fi
        if [ $kind = q ] && [ -n "${VOLE_ROOT:-}" ]; then
            # (and from the cache `check` makes, which records more than
            # a query's: what the queries need)
            rm -rf "$W/cache"
            (cd "$QDIR" && VOLE_CACHE="$W/cache" VOLE_CACHE_TRACE=/dev/null \
                "$COMPILER" check "$VOLE_ROOT") >/dev/null 2>&1 </dev/null
            run "$line" checked
            same_as_off checked || bad="$bad$(cat "$W/why")
"
        fi
        if [ $kind != q ] && ! grep -q '^hit$' "$W/warm.trace"; then
            # (an edit's cold run caches the program it wrote, or would
            # write, not the one it read: the cache of this state made by
            # `volec check` first, then the line)
            rm -rf "$W/cache"
            if [ $kind = w ]; then run '% volec check' primer; else run '% "$COMPILER" check' primer; fi
            rm -rf "$W/primer.tree"
            run "$line" primed
            same_as_off primed || bad="$bad$(cat "$W/why")
"
            rm -rf "$W/primed.tree"
        elif [ $kind = q ] && grep -q '^save$' "$W/cold.trace" && ! grep -q '^hit$' "$W/warm.trace"; then
            bad="${bad}the cold run wrote the cache, the warm one did not read it
"
        fi
        # (a line answered from the cache by one run at least)
        cat "$W"/*.trace 2>/dev/null | grep -q '^hit$' && hits=$((hits + 1))
        rm -f "$W"/*.trace
        if [ -n "$bad" ]; then
            {
                echo "  line $n: $line"
                printf '%s' "$bad" | sed 's/^/    /'
            } >>"$W/fails"
        fi
        if [ $kind != q ]; then
            rm -rf "$S" "$W/cold.tree" "$W/warm.tree"
            mv "$W/off.tree" "$S"
        fi
    done <"$W/lines"
    if [ -s "$W/fails" ]; then
        {
            echo "FAIL cachediff/$label ($lines lines, $hits from the cache):"
            cat "$W/fails"
        } >"$RES"
    else
        echo "pass cachediff/$label ($lines lines, $hits from the cache)" >"$RES"
    fi
    rm -rf "$W"
    exit 0
fi

COMPILER="$ROOT/target/volec"
JOBS=4
SAMPLE=0
ONLY=
while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || exit 2; COMPILER=$2; shift 2 ;;
        -j) [ $# -ge 2 ] || exit 2; JOBS=$2; shift 2 ;;
        --sample) SAMPLE=1; shift ;;
        -*) echo "usage: tests/cachediff/run.sh [-c COMPILER] [-j JOBS] [--sample] [NAME...]" >&2; exit 2 ;;
        *) ONLY="$ONLY $1"; shift ;;
    esac
done
case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "cachediff/run.sh: no compiler at $COMPILER" >&2; exit 2; }
export COMPILER

CD_WORK=$(mktemp -d "${TMPDIR:-/tmp}/vole-cachediff.XXXXXX")
CD_WORK=$(cd "$CD_WORK" && pwd -P)
export CD_WORK
trap 'rm -rf "$CD_WORK"' EXIT
trap 'exit 130' INT TERM
mkdir -p "$CD_WORK/res"

for f in "$ROOT"/tests/query/*.q "$ROOT"/tests/refactor/*.t "$ROOT"/examples/*/*/README.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    stem=${base%.*}
    case "$f" in
        */README.md)
            grep -q '^```console' "$f" || continue
            stem=$(basename "$(dirname "$f")")
            base=walkthrough:$stem
            # (as tests/walkthrough/run.sh: off macOS, not an example on
            # std::gpu, std::window or std::objc)
            if [ "$(uname -s)" != Darwin ] && find "$(dirname "$f")" -name '*.vl' -exec cat {} + \
                    | grep -vE '^[[:space:]]*//' | grep -qE 'std::(gpu|window|objc)|use std::\{[^}]*(gpu|window|objc)::'; then
                continue
            fi
            ;;
    esac
    if [ -n "$ONLY" ]; then
        keep=0
        for o in $ONLY; do
            [ "$o" = "$stem" ] || [ "$o" = "$base" ] && keep=1
        done
        [ $keep = 1 ] || continue
    elif [ $SAMPLE = 1 ]; then
        grep -qx "$base" "$HERE/sample" || continue
    fi
    printf '%s\n' "$f"
done >"$CD_WORK/files"
[ -s "$CD_WORK/files" ] || { echo "cachediff/run.sh: no transcript to run" >&2; exit 2; }

xargs -P "$JOBS" -n 1 sh "$HERE/run.sh" --one <"$CD_WORK/files"

STATUS=0
total=0
hits=0
for r in "$CD_WORK"/res/*; do
    cat "$r"
    head -1 "$r" | grep -q '^FAIL' && STATUS=1
    set -- $(head -1 "$r" | sed 's/.*(\([0-9]*\) lines, \([0-9]*\) from.*/\1 \2/')
    total=$((total + $1))
    hits=$((hits + $2))
done
n=$(wc -l <"$CD_WORK/files" | tr -d ' ')
got=$(ls "$CD_WORK/res" | wc -l | tr -d ' ')
if [ "$got" != "$n" ]; then
    echo "FAIL cachediff: $got of $n transcripts reported"
    STATUS=1
fi
# (0.25.3) `volec` run from $PATH, a name without a `/`, has the cache
# too (before, the compiler found no file to hash, and had none: no
# walkthrough line used it).
mkdir -p "$CD_WORK/bin"
ln -s "$COMPILER" "$CD_WORK/bin/volec"
: >"$CD_WORK/path.trace"
for _ in 1 2; do
    (cd "$ROOT/tests/query" && PATH="$CD_WORK/bin:$PATH" VOLE_ROOT=context/main.vl \
        VOLE_CACHE="$CD_WORK/path.cache" VOLE_CACHE_TRACE="$CD_WORK/path.trace" \
        volec query items >/dev/null 2>&1)
done
if [ "$(tr '\n' ' ' <"$CD_WORK/path.trace")" = "miss save hit " ]; then
    echo "pass cachediff/volec_in_path"
else
    echo "FAIL cachediff/volec_in_path: \`volec query items\` twice, from \$PATH: the cache's trace is '$(tr '\n' ' ' <"$CD_WORK/path.trace")', not 'miss save hit'"
    STATUS=1
fi
echo "cachediff: $n transcripts, $total lines compared, $hits answered from the cache$([ $STATUS = 0 ] || echo '; failed')"
exit $STATUS
