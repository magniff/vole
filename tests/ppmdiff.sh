#!/bin/sh
# (0.25.2) Compares an image a program wrote with a reference, for the
# `// EXPECT-PPM:` directive of tests/run.sh: both are PPM files (P6, or
# P3), the actual one cropped to a region first when one is given.
#
# usage: tests/ppmdiff.sh [-r X,Y,W,H] [-t N] [-p PERCENT] [-o CROPPED] ACTUAL REFERENCE
#   -r X,Y,W,H   compare only this region of ACTUAL (default: all of it);
#                the reference is either the region's size (a crop, the
#                usual) or ACTUAL's (then its same region is compared)
#   -t N         a pixel is the same when no channel differs by more than
#                N (default 0)
#   -p PERCENT   up to PERCENT of the pixels may differ (default 0; a
#                decimal, like 0.5)
#   -o CROPPED   writes ACTUAL's region there (P6), the file to commit as
#                the reference when the change is wanted
#
# Prints nothing and exits 0 when they agree; else one line (how many
# pixels differ, the worst one: where, the two colours) and exits 1;
# exit 2 when a file is not a PPM or the sizes cannot match, 3 when
# there is no REFERENCE (CROPPED is written all the same).

set -u
LC_ALL=C
export LC_ALL

REGION=""
TOL=0
PCT=0
OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        -r) [ $# -ge 2 ] || exit 2; REGION=$2; shift 2 ;;
        -t) [ $# -ge 2 ] || exit 2; TOL=$2; shift 2 ;;
        -p) [ $# -ge 2 ] || exit 2; PCT=${2%\%}; shift 2 ;;
        -o) [ $# -ge 2 ] || exit 2; OUT=$2; shift 2 ;;
        -*) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
        *) break ;;
    esac
done
[ $# -eq 2 ] || { echo "usage: tests/ppmdiff.sh [-r X,Y,W,H] [-t N] [-p PERCENT] [-o CROPPED] ACTUAL REFERENCE" >&2; exit 2; }
ACTUAL=$1
REF=$2
[ -f "$ACTUAL" ] || { echo "no image $ACTUAL"; exit 2; }

# The bytes of a file, one decimal number each, after a line naming it.
bytes() {
    echo "file $1"
    od -An -v -tu1 "$1"
}

# The awk below reads both files' bytes: the header (P6/P3, width,
# height, maxval, `#` comments), then the samples.
TMP=${TMPDIR:-/tmp}/ppmdiff.$$
trap 'rm -f "$TMP".*' EXIT
{ bytes "$ACTUAL"; [ -f "$REF" ] && bytes "$REF"; } >"$TMP.bytes"
awk -v region="$REGION" -v tol="$TOL" -v pct="$PCT" -v out="$TMP.crop" -v aname="$ACTUAL" -v rname="$REF" '
    function header(f,   tok, n, c, s, incomment) {
        # tokens: magic, width, height, maxval
        n = 0; s = ""; incomment = 0
        while (pos[f] <= len[f]) {
            c = b[f, pos[f]++]
            if (incomment) { if (c == 10 || c == 13) incomment = 0; continue }
            if (c == 35 && s == "") { incomment = 1; continue }
            if (c == 32 || c == 9 || c == 10 || c == 13) {
                if (s != "") { tok[++n] = s; s = ""; if (n == 4) break }
                continue
            }
            s = s sprintf("%c", c)
        }
        magic[f] = tok[1]; w[f] = tok[2] + 0; h[f] = tok[3] + 0; maxv[f] = tok[4] + 0
        if ((magic[f] != "P6" && magic[f] != "P3") || w[f] <= 0 || h[f] <= 0 || maxv[f] <= 0 || maxv[f] > 255)
            return 0
        if (magic[f] == "P3") {
            # the samples as text: rebuild them as numbers
            m = 0; s = ""
            while (pos[f] <= len[f]) {
                c = b[f, pos[f]++]
                if (c >= 48 && c <= 57) { s = s sprintf("%c", c); continue }
                if (s != "") { px[f, m++] = s + 0; s = "" }
            }
            if (s != "") px[f, m++] = s + 0
            cnt[f] = m
        } else {
            m = 0
            while (pos[f] <= len[f]) px[f, m++] = b[f, pos[f]++]
            cnt[f] = m
        }
        return cnt[f] >= w[f] * h[f] * 3
    }
    function sample(f, x, y, ch) { return px[f, (y * w[f] + x) * 3 + ch] }
    $1 == "file" { f++; len[f] = 0; pos[f] = 1; next }
    { for (i = 1; i <= NF; i++) b[f, ++len[f]] = $i }
    END {
        if (!header(1)) { printf "%s is not a PPM image (P6 or P3, maxval up to 255)\n", aname; exit 2 }
        x0 = 0; y0 = 0; rw = w[1]; rh = h[1]
        if (region != "") {
            if (split(region, r, ",") != 4) { printf "region %s: not X,Y,W,H\n", region; exit 2 }
            x0 = r[1] + 0; y0 = r[2] + 0; rw = r[3] + 0; rh = r[4] + 0
            if (rw <= 0 || rh <= 0 || x0 < 0 || y0 < 0 || x0 + rw > w[1] || y0 + rh > h[1]) {
                printf "region %s is not inside %s (%dx%d)\n", region, aname, w[1], h[1]; exit 2
            }
        }
        # the crop, as octal escapes for printf(1)
        printf "P6\n%d %d\n255\n", rw, rh > out
        for (y = 0; y < rh; y++) {
            line = ""
            for (x = 0; x < rw; x++)
                for (ch = 0; ch < 3; ch++)
                    line = line sprintf("\\%03o", int(sample(1, x0 + x, y0 + y, ch) * 255 / maxv[1]))
            print line > (out ".esc")
        }
        if (f < 2) { printf "no reference %s\n", rname; exit 3 }
        if (!header(2)) { printf "%s is not a PPM image (P6 or P3, maxval up to 255)\n", rname; exit 2 }
        if (w[2] == rw && h[2] == rh) { rx = 0; ry = 0 }
        else if (w[2] == w[1] && h[2] == h[1]) { rx = x0; ry = y0 }
        else {
            printf "the reference %s is %dx%d; the region compared is %dx%d (of %dx%d)\n", rname, w[2], h[2], rw, rh, w[1], h[1]
            exit 2
        }
        bad = 0; worst = -1
        for (y = 0; y < rh; y++)
            for (x = 0; x < rw; x++) {
                d = 0
                for (ch = 0; ch < 3; ch++) {
                    a = sample(1, x0 + x, y0 + y, ch) * 255 / maxv[1]
                    e = sample(2, rx + x, ry + y, ch) * 255 / maxv[2]
                    t = a > e ? a - e : e - a
                    if (t > d) d = t
                }
                if (d > tol) bad++
                if (d > worst) { worst = d; wx = x; wy = y }
            }
        n = rw * rh
        if (bad * 100 <= pct * n) exit 0
        ea = ""; ee = ""
        for (ch = 0; ch < 3; ch++) {
            ea = ea (ch ? "," : "") int(sample(1, x0 + wx, y0 + wy, ch) * 255 / maxv[1])
            ee = ee (ch ? "," : "") int(sample(2, rx + wx, ry + wy, ch) * 255 / maxv[2])
        }
        printf "%d of %d pixels (%.2f%%) differ by more than %d (allowed: %s%%); the worst at (%d,%d) of the region (%d,%d in the image): expected %s, got %s\n", \
            bad, n, bad * 100 / n, tol, pct, wx, wy, x0 + wx, y0 + wy, ee, ea
        exit 1
    }
' "$TMP.bytes"
rc=$?
if [ -n "$OUT" ] && [ -f "$TMP.crop" ]; then
    {
        cat "$TMP.crop"
        while IFS= read -r l; do
            # shellcheck disable=SC2059
            printf "$l"
        done <"$TMP.crop.esc"
    } >"$OUT"
fi
exit $rc
