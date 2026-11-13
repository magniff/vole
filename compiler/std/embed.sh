#!/bin/sh
# Makes compiler/src/front/stdsrc.vl from std's files (compiler/std):
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
# It writes std_source (the text), std_units (0.27.5: its units, made by
# the compiler, for a build that lexes only those it reaches), std_files
# (where each file's text starts in the text) and std_line_marks; and
# Gpa's implementation, std/rt/gpa.vl and (for --check-alloc)
# std/rt/alloc_check.vl, as std_gpa_source and std_check_gpa_source, and
# the target's system, rt/sys_macos.vl or rt/sys_linux.vl, as
# std_sys_source (front/stdalloc.vl's std_tail puts them after the text).
# Run it after changing any of them; tests/run.sh checks they agree, and
# the commit hook makes the file again when compiler/std changes.
#
# usage: compiler/std/embed.sh [-c]   (-c: only check, exit 1 if stale)
set -eu
# (0.27.5, Z5.2) std's index, std_units, is made by a compiler: the one
# VOLE_EMBED_VOLEC names, else target/tools/volec, else target/volec, of
# the caller's tree, then of this script's, then of the main checkout (the
# hooks run this script in a copy of std), the first that writes this
# format (STD_UNITS_FORMAT, front/modules/stdlazy.vl's INDEX_FORMAT).
# Its first line, `std-text SUM`, is the cksum of the text it was made
# for, and std_text_sum the text's: a build reads the index only when
# they agree. With no such compiler the index the file has is kept (made
# for another text, it is not read: a build lexes std whole), with a
# warning, never replaced by an empty one; and -c does not compare it.
STD_UNITS_FORMAT=1
caller=$(pwd)
here=$(cd "$(dirname "$0")/../.." && pwd)
embed_volec=${VOLE_EMBED_VOLEC:-}
case "$embed_volec" in ""|/*) ;; *) embed_volec=$caller/$embed_volec ;; esac
main_tree=
common=$(git -C "$caller" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
case "$common" in */.git) main_tree=${common%/.git} ;; esac
cd "$(dirname "$0")/../.."
out=compiler/src/front/stdsrc.vl
# (0.29) The text is made in the temporary directory, outside the tree,
# and is in the tree only for the last step: a copy beside the output
# (the same file system, so that mv is a rename and a reader never sees
# half a file), renamed at once. Before, the file being made sat beside
# the output for the whole run (seconds, with a compiler making the
# index), and a run killed outright (SIGKILL: a hook's timeout; no trap
# runs) left `stdsrc*.vl.XXXXXX` under compiler/src, which the tools then
# took for a changed source (tests/affected.sh: a broad plan).
# (0.28.0: removed on every way out, also an error's and a signal's)
tmp=
new=
work=
trap 'rm -rf "$work"; [ -z "$new" ] || rm -f "$new"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
work=$(mktemp -d "${TMPDIR:-/tmp}/vole-embed.XXXXXX")
tmp=$work/stdsrc.out
# std's root module: this file.
ROOT_FILES=std
dir=compiler/std
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
# (0.27.5, Z5.2) std's units, `volec __std-index TEXT`
units_made=0
text_sum=$(cksum <"$text" | awk '{ print $1 }')
for c in "$embed_volec" "$caller/target/tools/volec" "$caller/target/volec" \
    "$here/target/tools/volec" "$here/target/volec" \
    ${main_tree:+"$main_tree/target/tools/volec" "$main_tree/target/volec"}; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    # (0.29) Until 0.29 the command was `__std2-index` and the index's first
    # word `std2-units`: a compiler built before the rename (0.28.0, a
    # tools build older than it) is asked by the old name, and its first
    # line written as this format's (the units are the same). The second
    # name goes when no such build is in use.
    for cmd in __std-index __std2-index; do
        if "$c" "$cmd" "$text" >"$work/made" 2>/dev/null \
            && head -1 "$work/made" | grep -q -e "^std-units $STD_UNITS_FORMAT " -e "^std2-units $STD_UNITS_FORMAT "; then
            sed -e '1s/^std2-units /std-units /' "$work/made" >"$work/made.new"
            mv "$work/made.new" "$work/made"
            units_made=1
            break
        fi
    done
    [ "$units_made" = 1 ] && break
done
if [ "$units_made" = 1 ]; then
    { echo "std-text $text_sum"; cat "$work/made"; } | lines >"$work/units"
else
    # (the file's own, as it is: for another text, or none)
    [ -f "$out" ] && awk '/^pub fn std_units/ { on = 1; next } on && /^}/ { exit } on' "$out" >"$work/units"
    [ -f "$work/units" ] || : >"$work/units"
    if [ -s "$work/units" ] && [ "${1:-}" != "-c" ]; then
        echo "embed.sh: no compiler here writes std's index (format $STD_UNITS_FORMAT, volec 0.27.5 or later): $out's std_units kept as it was; a build lexes std whole until it is made again (try: VOLE_EMBED_VOLEC=target/volec compiler/std/embed.sh)" >&2
    fi
fi
{
    echo "// Generated by compiler/std/embed.sh from std's files (do not"
    echo "// edit): the standard library's source, its units' index, its"
    echo "// files and its line marks."
    echo ""
    echo "use crate::base::buf_str;"
    echo ""
    echo "pub fn std_source(out: i64) {"
    lines <"$text"
    echo "}"
    echo ""
    echo "// (0.27.5, Z5.2) std's units, for a build that lexes only those it"
    echo "// reaches (front/modules/stdlazy.vl: index_command writes it)"
    echo "pub fn std_units(out: i64) {"
    cat "$work/units"
    echo "}"
    echo ""
    echo "// (0.27.5, Z5.2) the cksum of std_source's text (std_units is read"
    echo "// only when its first line names the same)"
    echo "pub fn std_text_sum() -> i64 {"
    echo "    $text_sum"
    echo "}"
    echo ""
    echo "pub fn std_files(out: i64) {"
    lines <"$map"
    echo "}"
    echo ""
    echo "pub fn std_line_marks(out: i64) {"
    LC_ALL=C awk '(NR - 1) % 64 == 0 { print at + 0 } { at += length($0) + 1 }' "$text" | lines
    echo "}"
    echo ""
    echo "// (Z5) Gpa's implementation, std::__gpa (front/stdalloc.vl: std_tail)"
    echo "pub fn std_gpa_source(out: i64) {"
    lines <"$dir/rt/gpa.vl"
    echo "}"
    echo ""
    echo "// (Z5) the same with --check-alloc: the checking allocator"
    echo "pub fn std_check_gpa_source(out: i64) {"
    lines <"$dir/rt/alloc_check.vl"
    echo "}"
    echo ""
    echo "// (0.27.2.1) the target's system, std::__sys (front/stdalloc.vl: std_tail)"
    echo "pub fn std_sys_source(out: i64, linux: bool) {"
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
        nounits() { awk '/^pub fn std_units/ { skip = 1; next } skip && /^}/ { skip = 0; next } !skip' "$1"; }
        if [ "$(nounits "$tmp" | cksum)" = "$(nounits "$out" | cksum)" ]; then
            rm -f "$tmp"
            exit 0
        fi
    fi
    rm -f "$tmp"
    echo "$out is stale: run compiler/std/embed.sh" >&2
    exit 1
fi
new=$out.new.$$
cp "$tmp" "$new"
mv "$new" "$out"
new=
