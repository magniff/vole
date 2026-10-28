# (0.25.2) An EXPECT block against a program's stdout, both trimmed, line
# for line: a line of the block matches a line of the output when they are
# equal, or when the block's line has holes and the output's line fills
# them. The holes, written in an `// EXPECT:` line:
#   {num}   a number: 12, -3, 0.25, 1.5e-3 (sign, digits, a fraction, an
#           exponent)
#   {int}   an integer: 12, -3
#   {..}    any text, maybe none, within the line
# Every other character is itself (`{` included). Used by tests/run.sh:
#   awk -v want=EXPECTED -f tests/expect.awk ACTUAL
# exits 0 on a match; else prints the first line that differs (`line N:
# expected '...', got '...'`) and exits 1.

BEGIN {
    HOLE[1] = "{num}"; KIND[1] = "N"
    HOLE[2] = "{int}"; KIND[2] = "I"
    HOLE[3] = "{..}"; KIND[3] = "A"
    nw = 0
    while ((getline line < want) > 0) w[++nw] = line
}

{ a[++na] = $0 }

# The tokens of pattern p: tk[k] is L (literal text tv[k]), N, I or A.
function tokenize(p,   rest, best, bi, h, j) {
    nt = 0
    rest = p
    while (rest != "") {
        bi = 0
        for (h = 1; h <= 3; h++) {
            j = index(rest, HOLE[h])
            if (j > 0 && (bi == 0 || j < bi)) { bi = j; best = h }
        }
        if (bi == 0) { tk[++nt] = "L"; tv[nt] = rest; break }
        if (bi > 1) { tk[++nt] = "L"; tv[nt] = substr(rest, 1, bi - 1) }
        tk[++nt] = KIND[best]
        rest = substr(rest, bi + length(HOLE[best]))
    }
}

function is_number(t, kind) {
    if (kind == "I") return t ~ /^[-+]?[0-9]+$/
    return t ~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$/
}

# Whether s from position i matches the tokens from k on.
function at(s, i, k,   j, len, n) {
    if (k > nt) return i == length(s) + 1
    if (tk[k] == "L") {
        len = length(tv[k])
        if (substr(s, i, len) != tv[k]) return 0
        return at(s, i + len, k + 1)
    }
    if (tk[k] == "A") {
        for (j = i; j <= length(s) + 1; j++)
            if (at(s, j, k + 1)) return 1
        return 0
    }
    # a number: its longest run of number characters, then shorter ones
    n = 0
    if (match(substr(s, i), /^[-+0-9.eE]+/)) n = RLENGTH
    for (len = n; len >= 1; len--)
        if (is_number(substr(s, i, len), tk[k]) && at(s, i + len, k + 1)) return 1
    return 0
}

function same(p, s) {
    if (p == s) return 1
    if (index(p, "{num}") == 0 && index(p, "{int}") == 0 && index(p, "{..}") == 0) return 0
    tokenize(p)
    return at(s, 1, 1)
}

END {
    n = (na > nw ? na : nw)
    for (i = 1; i <= n; i++) {
        if (i > nw) { printf "line %d: expected the end of the output, got '%s'\n", i, a[i]; exit 1 }
        if (i > na) { printf "line %d: expected '%s', got the end of the output\n", i, w[i]; exit 1 }
        if (!same(w[i], a[i])) { printf "line %d: expected '%s', got '%s'\n", i, w[i], a[i]; exit 1 }
    }
    exit 0
}
