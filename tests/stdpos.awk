# (0.25.3) std's positions in a transcript, compared normalized, so that a
# change to std does not break transcripts that are not about std: the
# query, refactor, walkthrough and book runners pass both the transcript
# and what the compiler printed through this before comparing them. The
# files keep the real numbers (`-u` writes them); only the comparison
# ignores them.
#
#   awk -v mode=norm -f tests/stdpos.awk FILE     the comparison's text
#   awk -v mode=shift -f tests/stdpos.awk FILE    the same numbers moved
#                                                 (tests/stdpos/run.sh: a
#                                                 std change, simulated)
#   awk -v mode=has -f tests/stdpos.awk FILE      prints the number of
#                                                 lines it would change
#   awk -v mode=lines -f tests/stdpos.awk FILE    (0.25.5) as norm, line for
#                                                 line (std's modules kept
#                                                 a row each): what
#                                                 tests/stdkeep.sh matches
#
# What is std's (each number, in mode norm, becomes L, C or N):
#   - a position in std's text: <std>:LINE:COL, <std>:A-B, <std>:LINE, and
#     the same after <std::arch...> (`<std>:L:C`, `<std>:L-L`, `<std>:L`);
#   - a position in std's files in the repository:
#     compiler/std/FILE.vl:LINE:COL and :A-B (two numbers: one alone is
#     a FILE:LINE argument or grep -c's count);
#   - the leading LINE:COL, A-B or LINE of the rows under a header of
#     std (`# <std>`, `# std::io\t<std>`, `# ...compiler/std/x.vl`), as
#     refs, grep and items print them, up to the first row that does not
#     start with a number;
#   - a std module's item count, `std::gpu\t<std>\t176` (query items'
#     summary, query modules), and a std item's count of references,
#     `197\tstd::Vec::push` (refs --count);
#   - (0.25.5) which modules std has and their order: a command's rows of
#     std's modules (`std::gpu\t<std>\t176`, as `items` lists them after
#     the program's) are one line, `std\t<std>\t(std's modules)`, where
#     the first was;
#   - (0.25.5) with -v stdfiles="std.vl flat/alloc.vl ..." (std's files,
#     relative to compiler/std: the LSP runner), a position in one of
#     them as the LSP writes it: `at std.vl:303:37` in a hover, and the
#     range after a `.../std-@STD@/FILE.vl` uri.
# A program's own positions are left as they are. `$ ` and `% ` lines
# (the commands) are never changed.
#
# A transcript about std's positions themselves opts out: a line
# `## exact-std` (in a README, `<!-- exact-std -->`) near its top, and
# the runner then compares it exactly (does not call this).

function num(n, kind) {
    if (mode == "shift") return n + (kind == "C" ? 3 : 7)
    return kind
}

# Every <std...>:N[:N|-N] in s.
function inline_std(s,    out, pre, m, tail, parts, k, sep) {
    out = ""
    while (match(s, /<std(::[A-Za-z0-9_]+)*>:[0-9]+([:-][0-9]+)?/)) {
        pre = substr(s, 1, RSTART - 1)
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        k = index(m, ">:")
        out = out pre substr(m, 1, k + 1) numbers(substr(m, k + 2))
    }
    return out s
}

# Every compiler/std/FILE.vl:N:N or :N-N in s.
function file_std(s,    out, pre, m, k) {
    out = ""
    while (match(s, /compiler\/std\/[A-Za-z0-9_\/]+\.vl:[0-9]+[:-][0-9]+/)) {
        pre = substr(s, 1, RSTART - 1)
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        k = index(m, ".vl:")
        out = out pre substr(m, 1, k + 3) numbers(substr(m, k + 4))
    }
    return out s
}

# "N", "N:N" or "N-N": a line, a line and column, or a range.
function numbers(p,    i, a, b) {
    i = index(p, ":")
    if (i > 0) return num(substr(p, 1, i - 1), "L") ":" num(substr(p, i + 1), "C")
    i = index(p, "-")
    if (i > 0) return num(substr(p, 1, i - 1), "L") "-" num(substr(p, i + 1), "L")
    return num(p, "L")
}

BEGIN { if (mode == "") mode = "norm"; changed = 0 }

{
    line = $0
    if (line ~ /^[$%] /) { instd = 0; mods = 0; emit(line); next }
    # (0.25.5) std's modules, as `items` lists them (`std::gpu\t<std>\t180`):
    # which there are and their order are std's shape, which a std change
    # alters; in mode norm a command's rows of them are one line, where
    # the first was (a program's own modules among them are kept)
    if (mode == "norm" && line ~ /^std(::[A-Za-z0-9_]+)*\t(<std(::[A-Za-z0-9_]+)*>|[^\t]*compiler\/std\/[^\t]*\.vl)\t[0-9]+$/) {
        instd = 0
        if (!mods++) emit("std\t<std>\t(std's modules)")
        else changed++
        next
    }
    if (line ~ /^# /) {
        instd = (line ~ /^# ([^\t]*\t)?<std(::[A-Za-z0-9_]+)*>$/ || line ~ /^# ([^\t]*\t)?[^\t]*compiler\/std\/[^\t]*\.vl$/)
    } else if (instd && match(line, /^[0-9]+([:-][0-9]+)?\t/)) {
        line = numbers(substr(line, 1, RLENGTH - 1)) substr(line, RLENGTH)
    } else {
        instd = 0
        if (line ~ /^std(::[A-Za-z0-9_]+)*\t(<std(::[A-Za-z0-9_]+)*>|[^\t]*compiler\/std\/[^\t]*\.vl)\t[0-9]+$/) {
            match(line, /[0-9]+$/)
            line = substr(line, 1, RSTART - 1) num(substr(line, RSTART), "N")
        } else if (line ~ /^[0-9]+\t<?std::[^\t]*$/) {
            match(line, /^[0-9]+/)
            line = num(substr(line, 1, RLENGTH), "N") substr(line, RLENGTH + 1)
        }
    }
    line = file_std(inline_std(line))
    if (stdfiles != "") line = lsp_std(line)
    emit(line)
}

# (0.25.5) The LSP's positions in std's files: a hover's `at FILE:L:C`
# (FILE one of stdfiles) and the range after a uri of std's cache
# (`/std-@STD@/FILE","range":{"start":{"line":L,"character":C},"end":...}`).
function lsp_std(s,    out, pre, m, k, rest, n, i, names) {
    if (!lsp_init) {
        n = split(stdfiles, names, " ")
        for (i = 1; i <= n; i++) if (names[i] != "") isstd[names[i]] = 1
        lsp_init = 1
    }
    out = ""
    while (match(s, /[ `'("]at [A-Za-z0-9_\/]+\.vl:[0-9]+:[0-9]+/)) {
        pre = substr(s, 1, RSTART - 1)
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        k = index(m, ".vl:")
        if (substr(m, 5, k - 2) in isstd)
            out = out pre substr(m, 1, k + 3) numbers(substr(m, k + 4))
        else
            out = out pre m
    }
    s = out s
    out = ""
    while (match(s, /\/std-@STD@\/[^"]*","range":\{"start":\{"line":[0-9]+,"character":[0-9]+\},"end":\{"line":[0-9]+,"character":[0-9]+\}/)) {
        pre = substr(s, 1, RSTART - 1)
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        k = index(m, "\"range\"")
        rest = substr(m, k)
        out = out pre substr(m, 1, k - 1) lsp_range(rest)
    }
    return out s
}

# `"range":{"start":{"line":L,"character":C},"end":{...}}` with its numbers
# as num() makes them (L, C; or moved).
function lsp_range(r,    out, v) {
    out = ""
    while (match(r, /"(line|character)":[0-9]+/)) {
        v = substr(r, RSTART, RLENGTH)
        out = out substr(r, 1, RSTART - 1)
        if (v ~ /^"line"/) out = out "\"line\":" num(substr(v, 8), "L")
        else out = out "\"character\":" num(substr(v, 13), "C")
        r = substr(r, RSTART + RLENGTH)
    }
    return out r
}

function emit(l) {
    if (l != $0) changed++
    if (mode != "has") print l
}

END { if (mode == "has") print changed }
