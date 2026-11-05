#!/bin/sh
# The borrow checker's rustc twin (0.27.1): every rust-edition case given is
# compiled by rustc too, and rustc's verdict (accept or reject) must be the
# case's. Verdicts only, not messages.
#
# usage: tools/borrowck-twin.sh [-v] [-r RUSTC] CASE...
#
#   -v        print every case's line (default: only mismatches and the
#             summary)
#   -r RUSTC  the rustc to run (default: rustc on PATH, else
#             ~/.cargo/bin/rustc); none found: exit 77 (a gate SKIP)
#
# A case is turned into Rust by blanking its `// KEY: ...` directive lines
# and rewriting `println(` to `println!(` (the one spelling of the common
# subset that is not Rust's), then compiled with
#   rustc --edition 2021 --crate-type bin -C panic=abort -A warnings
#         -D static-mut-refs --emit=metadata -o TMP
# (`static-mut-refs` is Rust 2024's rule, borrowck.static_mut_ref's; the
# borrow check runs for metadata, so nothing is generated or linked, and
# `-o /dev/null` fails: rustc makes its temporary directory beside it).
#
# The case's expectation: rejected when it has an `// ERROR:` line, with
# the first `borrowck.CODE` named in them as its code; accepted otherwise.
# rustc's first `error[E0xxx]` (or its first error without a code, by its
# message) maps to a borrowck code by the table below (docs/design/
# borrowck.md §14.1's rustc column); a rejection must
# map to the case's code. A case that diverges from rustc on purpose says
# so, with a class of docs/design/borrowck.md's divergences:
#   // RUSTC: accepts CLASS why    (the case is rejected, rustc accepts it)
#   // RUSTC: rejects CLASS why    (the case is accepted, rustc rejects it)
# CLASS one of R1-R10 (vole more permissive, or R8's Box) and L1-L6 (vole
# stricter).
#   // RUSTC: none why              (outside the common subset: not run)
# A marked divergence where rustc agrees with the case is a mismatch too
# (the marker is stale). An `XFAIL` case is checked the same: its
# directives say what the checker is to do, not what it does today.
#
# Prints `borrowck-twin: N cases, A agree, D divergences (CLASS n ...), S
# outside the subset, F mismatches`; exit 1 when F > 0.

VERBOSE=0
RUSTC=
while [ $# -gt 0 ]; do
    case "$1" in
        -v) VERBOSE=1 ;;
        -r) RUSTC=$2; shift ;;
        -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --) shift; break ;;
        -*) echo "borrowck-twin: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done
if [ -z "$RUSTC" ]; then
    RUSTC=$(command -v rustc 2>/dev/null)
    [ -n "$RUSTC" ] || RUSTC="$HOME/.cargo/bin/rustc"
fi
if [ ! -x "$RUSTC" ] && ! command -v "$RUSTC" >/dev/null 2>&1; then
    echo "borrowck-twin: SKIP: no rustc (install rustup's stable, or -r RUSTC)"
    exit 77
fi
[ $# -gt 0 ] || { echo "usage: tools/borrowck-twin.sh [-v] [-r RUSTC] CASE..." >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/borrowck-twin.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

# rustc's code -> borrowck's (docs/design/borrowck.md, the codes)
map_code() {
    case "$1" in
        E0499) echo mut_twice ;;
        E0502) echo conflict ;;
        E0503) echo use_borrowed ;;
        E0506) echo assign_borrowed ;;
        E0505) echo move_borrowed ;;
        E0597|E0713|E0716) echo dropped_borrowed ;;
        E0515) echo return_local ;;
        E0621|E0623|lifetime) echo outlives ;;
        E0106) echo elision ;;
        E0392) echo unused_param ;;
        E0382) echo use_moved ;;
        E0381) echo assign_moved_part ;;
        E0384) echo assign_twice ;;
        E0507|E0508) echo move_out ;;
        E0509) echo move_from_drop ;;
        E0510|E0594|E0596) echo guard_write ;;  # (E0594: in a guard, a `ref mut` binding is read-only)
        E0796|static_mut) echo static_mut_ref ;;
        *) echo "?$1" ;;
    esac
}

N=0 AGREE=0 DIV=0 SKIPN=0 FAILN=0
: >"$WORK/classes"
for case_ in "$@"; do
    N=$((N + 1))
    name=$(basename "$case_" .vl)
    [ -f "$case_" ] || { echo "FAIL $name: no such file $case_"; FAILN=$((FAILN + 1)); continue; }
    # the expectation and the marker
    want=$(awk '/^[ \t]*\/\/ ERROR:/ { if (match($0, /borrowck\.[a-z_0-9]+/)) { print substr($0, RSTART + 9, RLENGTH - 9); found = 1; exit } else other = 1 }
        END { if (!found && other) print "?other" }' "$case_")
    mark=$(awk '/^[ \t]*\/\/ RUSTC:/ { sub(/^[ \t]*\/\/ RUSTC:[ \t]*/, ""); print; exit }' "$case_")
    mverb=$(echo "$mark" | awk '{ print $1 }')
    mclass=$(echo "$mark" | awk '{ print $2 }')
    if [ "$mverb" = none ]; then
        SKIPN=$((SKIPN + 1))
        [ $VERBOSE = 1 ] && echo "none $name: ${mark#none }"
        continue
    fi
    if [ -n "$mark" ]; then
        case "$mverb $mclass" in
            "accepts "[LR][1-9]|"rejects "[LR][1-9]|"accepts R10"|"rejects R10") ;;
            *) echo "FAIL $name: bad marker '// RUSTC: $mark' (accepts|rejects R1-R10|L1-L6, or none)"
               FAILN=$((FAILN + 1)); continue ;;
        esac
    fi
    rs="$WORK/$name.rs"
    awk '{ if ($0 ~ /^[ \t]*\/\/ [A-Z][A-Z0-9-]*(\([^)]*\))?:/) print ""; else print }' "$case_" \
        | sed -E 's/(^|[^A-Za-z0-9_!])println\(/\1println!(/g' >"$rs"
    if "$RUSTC" --edition 2021 --crate-type bin -C panic=abort -A warnings -D static-mut-refs \
        --emit=metadata -o "$WORK/out.rmeta" "$rs" >"$WORK/out" 2>&1; then
        got=accept
    else
        got=reject
        first=$(awk '/^error\[E[0-9]+\]/ { print substr($0, 7, 5); exit }
            /^error: lifetime may not live long enough/ { print "lifetime"; exit }
            /^error: creating a (shared|mutable) reference to mutable static/ { print "static_mut"; exit }
            /^error: / && !/^error: aborting/ { print "other"; exit }' "$WORK/out")
        gotcode=$(map_code "$first")
    fi
    msg=$(awk '/^error/ && !/^error: aborting/ { print; exit }' "$WORK/out" | cut -c1-120)
    if [ -z "$want" ]; then wantv=accept; else wantv=reject; fi
    if [ "$got" = "$wantv" ] && [ -z "$mark" ]; then
        if [ $got = reject ] && [ "$gotcode" != "$want" ]; then
            echo "FAIL $name: both reject, but rustc's $first is borrowck.$gotcode, the case's borrowck.$want: $msg"
            FAILN=$((FAILN + 1))
        else
            AGREE=$((AGREE + 1))
            [ $VERBOSE = 1 ] && echo "ok   $name: ${got}s${first:+ $first = borrowck.$gotcode}"
        fi
    elif [ "$got" = "$wantv" ]; then
        echo "FAIL $name: marked '// RUSTC: $mark', but rustc ${got}s it as the case does (a stale marker)${first:+: $msg}"
        FAILN=$((FAILN + 1))
    elif [ -n "$mark" ] && [ "${mverb%s}" = "$got" ]; then
        DIV=$((DIV + 1))
        echo "$mclass" >>"$WORK/classes"
        [ $VERBOSE = 1 ] && echo "div  $name: rustc ${got}s ($mclass)${first:+: $msg}"
    else
        if [ $wantv = reject ]; then
            echo "FAIL $name: the case expects borrowck.$want, rustc accepts it"
        else
            echo "FAIL $name: the case is accepted, rustc rejects it: $msg"
        fi
        FAILN=$((FAILN + 1))
    fi
done
classes=$(sort "$WORK/classes" | uniq -c | awk '{ printf "%s%s %d", sep, $2, $1; sep = ", " }')
echo "borrowck-twin: $N cases, $AGREE agree, $DIV divergences${classes:+ ($classes)}, $SKIPN outside the subset, $FAILN mismatches"
[ $FAILN -eq 0 ]
