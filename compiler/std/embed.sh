#!/bin/sh
# Makes compiler/src/front/stdsrc_rust.vl from std's files (compiler/std2):
# the standard library's source, built into the compiler as functions that
# write it to a buffer (string literals cannot span lines: a call for each
# few lines, 0.21).
#
# std is a crate of its own (0.20): its root module is std.vl. A `mod
# NAME;` line of a file is the module NAME, in NAME.vl or NAME/mod.vl, and
# so on down (a module in a.vl has its children in a/, as in any program).
# The built-in text is the root's file, then each module as `mod NAME {
# ... }` after its parent's text (its `mod NAME;` line stays, and the
# compiler reads the braces instead: front/modules), each between banners
# `// ---- mod std::NAME ----` and `// ---- end mod std::NAME ----`.
#
# It writes std2_source (the text), std2_units (0.27.5: its units, made by
# the compiler, for a build that lexes only those it reaches), std2_files
# (where each file's text starts in the text) and std2_line_marks; and
# Gpa's implementation, std2/rt/gpa.vl and (for --check-alloc)
# std2/rt/alloc_check.vl, as std2_gpa_source and std2_check_gpa_source, and
# the target's system, rt/sys_macos.vl or rt/sys_linux.vl, as
# std2_sys_source (front/stdalloc.vl's std2_tail puts them after the text).
# Run it after changing any of them; tests/run.sh checks they agree, and
# the commit hook makes the file again when compiler/std2 changes.
#
# usage: compiler/std/embed.sh [--edition rust] [-c]   (-c: only check,
# exit 1 if stale; --edition rust: accepted, and means nothing: 0.27's
# flag, when the script also made the old std's text)
set -eu
# (0.27.5, Z5.2) std2's index, std2_units, is made by a compiler: the one
# VOLE_EMBED_VOLEC names, else target/tools/volec, else target/volec, of
# the caller's tree, then of this script's, then of the main checkout (the
# hooks run this script in a copy of std), the first that writes this
# format (STD2_UNITS_FORMAT, front/modules/std2lazy.vl's INDEX_FORMAT).
# Its first line, `std2-text SUM`, is the cksum of the text it was made
# for, and std2_text_sum the text's: a build reads the index only when
# they agree. With no such compiler the index the file has is kept (made
# for another text, it is not read: a build lexes std2 whole), with a
# warning, never replaced by an empty one; and -c does not compare it.
STD2_UNITS_FORMAT=1
caller=$(pwd)
here=$(cd "$(dirname "$0")/../.." && pwd)
embed_volec=${VOLE_EMBED_VOLEC:-}
case "$embed_volec" in ""|/*) ;; *) embed_volec=$caller/$embed_volec ;; esac
main_tree=
common=$(git -C "$caller" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
case "$common" in */.git) main_tree=${common%/.git} ;; esac
cd "$(dirname "$0")/../.."
if [ "${1:-}" = "--edition" ]; then
    [ "${2:-}" = rust ] || { echo "embed.sh: --edition takes rust" >&2; exit 2; }
    shift 2
fi
out=compiler/src/front/stdsrc_rust.vl
# (next to the output: writable in a sandbox that only allows the tree, and mv is a rename)
tmp=$(mktemp "$out.XXXXXX")
work=$(mktemp -d "${TMPDIR:-/tmp}/vole-embed.XXXXXX")
trap 'rm -rf "$work"' EXIT
# std's root module: this file.
ROOT_FILES=std
dir=compiler/std2
# (std's files beside this script, when there is no compiler/std2)
[ -f "$dir/std.vl" ] || dir=compiler/std
text=$work/text
map=$work/map
: >"$text"
: >"$map"

# The text of module PATH (std, std::a): its files (FILES, relative to $dir,
# without `.vl`), then its modules; NESTED: the directory (relative, with
# its `/`, or empty) where its `mod NAME;` lines find their files. A
# subshell: its variables are its own.
walk() (
    path=$1
    nested=$2
    shift 2
    files=""
    for f in "$@"; do
        [ -f "$dir/$f.vl" ] || continue
        files="$files $dir/$f.vl"
        echo "$(wc -c <"$text" | tr -d ' ') $f.vl" >>"$map"
        cat "$dir/$f.vl" >>"$text"
    done
    mods=$work/mods.$(echo "$path" | tr ':' '_')
    # shellcheck disable=SC2086
    cat $files |
        sed -n 's/^\(pub \)\{0,1\}mod \([A-Za-z_][A-Za-z0-9_]*\);.*$/\1\2/p' >"$mods"
    while read -r m; do
        vis=""
        name=$m
        case "$m" in "pub "*) vis="pub "; name=${m#pub } ;; esac
        if [ -f "$dir/$nested$name.vl" ]; then
            file=$nested$name
        elif [ -f "$dir/$nested$name/mod.vl" ]; then
            file=$nested$name/mod
        else
            echo "embed.sh: no file for module $path::$name ($dir/$nested$name.vl)" >&2
            exit 1
        fi
        printf '// ---- mod %s::%s ----\n%smod %s {\n' "$path" "$name" "$vis" "$name" >>"$text"
        walk "$path::$name" "$nested$name/" "$file"
        printf '// ---- end mod %s::%s ----\n}\n' "$path" "$name" >>"$text"
    done <"$mods"
)
# shellcheck disable=SC2086
walk std "" $ROOT_FILES
wc -c <"$text" | tr -d ' ' >>"$map"

# (sed, not awk: awks differ on backslashes in replacements.)
# (0.21) Up to about 2000 bytes of lines in one call: a program's std is
# 20 thousand lines, and a call for each cost more than reading it.
lines() {
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
        LC_ALL=C awk '{
            if (n > 0 && n + length($0) > 2000) { print "    buf_str(out, c\"" acc "\");"; acc = ""; n = 0 }
            acc = acc $0 "\\n"
            n += length($0) + 2
        }
        END { if (n > 0) print "    buf_str(out, c\"" acc "\");" }'
}
# (0.27.5, Z5.2) std2's units, `volec --edition rust __std2-index TEXT`
units_made=0
text_sum=$(cksum <"$text" | awk '{ print $1 }')
for c in "$embed_volec" "$caller/target/tools/volec" "$caller/target/volec" \
    "$here/target/tools/volec" "$here/target/volec" \
    ${main_tree:+"$main_tree/target/tools/volec" "$main_tree/target/volec"}; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    if "$c" --edition rust __std2-index "$text" >"$work/made" 2>/dev/null \
        && head -1 "$work/made" | grep -q "^std2-units $STD2_UNITS_FORMAT "; then
        units_made=1
        break
    fi
done
if [ "$units_made" = 1 ]; then
    { echo "std2-text $text_sum"; cat "$work/made"; } | lines >"$work/units"
else
    # (the file's own, as it is: for another text, or none)
    [ -f "$out" ] && awk '/^pub fn std2_units/ { on = 1; next } on && /^}/ { exit } on' "$out" >"$work/units"
    [ -f "$work/units" ] || : >"$work/units"
    if [ -s "$work/units" ] && [ "${1:-}" != "-c" ]; then
        echo "embed.sh: no compiler here writes std2's index (format $STD2_UNITS_FORMAT, volec 0.27.5 or later): $out's std2_units kept as it was; a build lexes std2 whole until it is made again (try: VOLE_EMBED_VOLEC=target/volec compiler/std/embed.sh)" >&2
    fi
fi
{
    echo "// Generated by compiler/std/embed.sh from std's files (do not"
    echo "// edit): the standard library's source, its units' index, its"
    echo "// files and its line marks."
    echo ""
    echo "use crate::base::buf_str;"
    echo ""
    echo "pub fn std2_source(out: i64) {"
    lines <"$text"
    echo "}"
    echo ""
    echo "// (0.27.5, Z5.2) std2's units, for a build that lexes only those it"
    echo "// reaches (front/modules/std2lazy.vl: index_command writes it)"
    echo "pub fn std2_units(out: i64) {"
    cat "$work/units"
    echo "}"
    echo ""
    echo "// (0.27.5, Z5.2) the cksum of std2_source's text (std2_units is read"
    echo "// only when its first line names the same)"
    echo "pub fn std2_text_sum() -> i64 {"
    echo "    $text_sum"
    echo "}"
    echo ""
    echo "pub fn std2_files(out: i64) {"
    lines <"$map"
    echo "}"
    echo ""
    echo "pub fn std2_line_marks(out: i64) {"
    LC_ALL=C awk '(NR - 1) % 64 == 0 { print at + 0 } { at += length($0) + 1 }' "$text" | lines
    echo "}"
    echo ""
    echo "// (Z5) Gpa's implementation, std::__gpa (front/stdalloc.vl: std2_tail)"
    echo "pub fn std2_gpa_source(out: i64) {"
    lines <"$dir/rt/gpa.vl"
    echo "}"
    echo ""
    echo "// (Z5) the same with --check-alloc: the checking allocator"
    echo "pub fn std2_check_gpa_source(out: i64) {"
    lines <"$dir/rt/alloc_check.vl"
    echo "}"
    echo ""
    echo "// (0.27.2.1) the target's system, std::__sys (front/stdalloc.vl: std2_tail)"
    echo "pub fn std2_sys_source(out: i64, linux: bool) {"
    echo "    if linux {"
    lines <"$dir/rt/sys_linux.vl" | sed 's/^/    /'
    echo "    } else {"
    lines <"$dir/rt/sys_macos.vl" | sed 's/^/    /'
    echo "    }"
    echo "}"
} >"$tmp"
if [ "${1:-}" = "-c" ]; then
    if cmp -s "$tmp" "$out"; then rm -f "$tmp"; exit 0; fi
    # (no compiler here made the index: the rest compared; one that can
    # makes it, and an empty or other index is then stale)
    if [ "$units_made" = 0 ]; then
        nounits() { awk '/^pub fn std2_units/ { skip = 1; next } skip && /^}/ { skip = 0; next } !skip' "$1"; }
        if [ "$(nounits "$tmp" | cksum)" = "$(nounits "$out" | cksum)" ]; then
            rm -f "$tmp"
            exit 0
        fi
    fi
    rm -f "$tmp"
    echo "$out is stale: run compiler/std/embed.sh" >&2
    exit 1
fi
mv "$tmp" "$out"
