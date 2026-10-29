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
#     `197\tstd::Vec::push` (refs --count).
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
    if (line ~ /^[$%] /) { instd = 0; emit(line); next }
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
    emit(line)
}

function emit(l) {
    if (l != $0) changed++
    if (mode != "has") print l
}

END { if (mode == "has") print changed }
