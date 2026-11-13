#!/usr/bin/env python3
"""Removes the `// EDITION: rust` line from the tree (0.28.0: one edition,
the line says nothing), and moves the line numbers written against the
files it shortens.

usage: tools/strip-edition.py [--dry-run] [--keep PATH]... [--list] [PATH...]
       tools/strip-edition.py --check-rerecord [PATH...]

  --dry-run   change nothing; print the same report
  --keep PATH one more path or prefix (ends with /) left as it is
  --list      print every file changed, not only the counts per directory
  PATH...     strip only the files under these paths (a file, or a
              directory); the positions written against them are moved
              wherever they are written, in the whole tree
  --check-rerecord
              after transcripts were recorded again (`run.sh -u` of
              tests/query, refactor, lsp, walkthrough): the changed .t,
              .q, .lsp and README.md files (against HEAD, under PATH...)
              whose difference is more than numbers and edition lines are
              listed, to be read by hand; exit 1 when there is one

What is removed, in a file git tracks:
  - a whole line `// EDITION: rust` (a .vl file, a text a test feeds to a
    tool, a here-document of a script, a file's text shown in a transcript
    or a README's session, there also as `> // EDITION: rust` and, a
    diff's context line, with one space before it);
  - in a grammar snapshot (.snap), the line and the scope lines under it;
  - the line inside a string, with its newline as the two characters `\\n`
    (`printf '// EDITION: rust\\nfn main() {}\\n'`, also `\\r\\n`);
  - an awk statement that only prints it (`print "// EDITION: rust"`).

What is kept (KEEP below, and --keep): what the previous release reads.
0.27.8 builds compiler/src and takes its edition from the line in
compiler/src/main.vl, and tests/compile_cost.sh gives it the programs of
tests/cost and its own hello world. compiler/src is not touched at all:
what it says about the line is the compiler's change, and the embedded
std is made from the stripped std by the commit hook. The records of
earlier releases (HISTORY) are not touched either.

What is moved, when a line goes from a place other than a file's end:
every position after it, in the forms the runners compare (tests/run.sh,
tests/directives.awk, the transcript runners; `N` becomes N less the lines
removed above it):
  - `FILE:N`, `FILE:N:C`, `FILE:N-M`, anywhere in any file, when FILE names
    a stripped file: beside the one that says it, in the directory named
    like it (tests/query/NAME.q and NAME/), one directory up, from the
    root, or beside a `// SOURCE:` program;
  - `FILE: line N[, column C]` the same way;
  - `FILE:N` of a file the text writes itself with the line in it, below
    where it writes it (a README's `cat > old.vl <<'EOF'`, a transcript's
    `printf '// EDITION: rust\\n...' > main.vl`);
  - `line N, column C` in a directive of the stripped file itself (ERROR,
    WARNING, STDERR, XFAIL, EXPECT, TRY, FIXED), and `line N` alone in an
    ERROR or WARNING directive (`the '{' at line 8`), not after `output:`;
  - `at N:C` in an ERROR or WARNING directive;
  - `CODE@N:C` in an XFAIL note, after the word `rust` (the positions
    before it are the old edition's, of a file that had no such line).

What is not handled, and is listed at the end of the report:
  - a line number with no file name beside it in a program's output or a
    transcript (a count of lines, a range `47-52`, `@@ -1,5 +1,4 @@`, an
    LSP position, a number an EXPECT prints): the transcripts whose text
    or programs changed are named `re-record`, and the runner says which
    of them differ (`tests/query/run.sh -u`, then --check-rerecord); a
    README's prose that names a line in words is read by hand;
  - `line N, column C` with no file name in a program of several files,
    when a module of it lost no line: moved as the root's, named `run
    these` (the case's own run says which were a module's);
  - a script or a source that reads or writes the line otherwise (`grep -q
    '^// EDITION: rust'`, a conditional `print`): named with the line;
  - `--edition` and VOLE_EDITION, wherever they are used: named;
  - a mention in prose: counted.

A second run finds nothing to do: a position is moved only in the run
that removes the line above it.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# What the previous release reads (see above), and this tool's own files.
KEEP = [
    "compiler/src/",
    "tests/cost/",
    "tests/compile_cost.sh",
    "tests/run/edition_line_comment.vl",
    "tools/strip-edition.py",
    "tools/test-strip-edition.py",
    "tools/mvs-census.py",
]
# The records of earlier releases and the notes of their work.
HISTORY = [
    "docs/releases.md",
    "docs/roadmap.md",
    "docs/design/",
    "bootstrap/releases.toml",
    "feedbacks/",
    "editors/vscode/CHANGELOG.md",
]

TEXT = "// EDITION: rust"
LINE = re.compile(r"^// EDITION: rust[ \t]*$")
# A file's text shown: a README's here-document (`> `), a diff's context
SHOWN = re.compile(r"^(?:> ?| )// EDITION: rust[ \t]*$")
SNAP = re.compile(r"^>// EDITION: rust[ \t]*$")
AWK_PRINT = re.compile(r'^\s*print "// EDITION: rust"\s*;?\s*$')
IN_STRING = re.compile(r"// EDITION: rust(?:\\r)?\\n")
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?")
WRITES = re.compile(r">\s*\"?(?:[^\s\"']*/)?([\w.-]+\.(?:vl|tach))\b")
USES = re.compile(r"--edition\b|\bVOLE_EDITION\b")

FILE_POS = re.compile(r"(?<![\w/.-])((?:[\w.-]+/)*[\w-][\w.-]*\.(?:vl|tach)):(\d+)(?:-(\d+)(?![\d:.]))?(?![\d.])")
FILE_LINE = re.compile(r"(?<![\w/.-])((?:[\w.-]+/)*[\w-][\w.-]*\.(?:vl|tach)): line (\d+)\b")
BARE_LINE_COL = re.compile(r"(?<!: )\bline (\d+)(?=, column \d+)")
BARE_LINE = re.compile(r"(?<!: )\bline (\d+)\b(?!, column)")
AT_POS = re.compile(r"\bat (\d+)(?=:\d+\b)")
CODE_POS = re.compile(r"@(\d+)(?=:\d+\b)")
DIRECTIVE = re.compile(r"^\s*//\s?(ERROR|WARNING|STDERR|XFAIL(?:\([^)]*\))?|EXPECT|TRY|FIXED)\s*:")
SOURCE = re.compile(r"^\s*//\s?SOURCE:\s*(\S+)", re.M)

PROGRAM_EXT = (".vl", ".tach")
TRANSCRIPT_EXT = (".t", ".q", ".lsp")
CODE_EXT = (".sh", ".awk", ".py", ".pl", ".js", ".ts", ".json", ".vl", ".tach", "")


def under(path, prefixes):
    for p in prefixes:
        if path == p or (p.endswith("/") and path.startswith(p)):
            return True
    return False


def tracked():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    paths = []
    for p in out.decode().split("\0"):
        full = os.path.join(ROOT, p)
        if p and os.path.isfile(full) and not os.path.islink(full):
            paths.append(p)
    return paths


def read(path):
    """The file's text, or None for one that is not text."""
    with open(os.path.join(ROOT, path), "rb") as f:
        data = f.read()
    if b"\0" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def write(path, text):
    with open(os.path.join(ROOT, path), "w", encoding="utf-8", newline="") as f:
        f.write(text)


def is_program(path):
    base = os.path.basename(path)
    return (path.endswith(PROGRAM_EXT) or "/texts/" in path or "/inputs/" in path
            or re.search(r"\.vl\.[\w-]+~$", base) is not None)


def group(path):
    parts = path.split("/")
    if len(parts) > 2 and parts[0] in ("tests", "compiler", "examples", "tools", "editors", "bench"):
        return "/".join(parts[:2])
    return parts[0] if len(parts) > 1 else "(root)"


def strip_text(path, text):
    """(the text without its edition lines, the 1-based numbers of the
    lines removed, how many were inside strings, the lines removed from
    files the text itself writes: (index of the first line after, the
    file's name, the line's number in that file))."""
    lines = text.split("\n")
    out = []
    removed = []
    strings = 0
    written = []
    program = is_program(path)
    snap = path.endswith(".snap")
    in_snap = False
    here = None
    for i, raw in enumerate(lines, 1):
        line = raw[:-1] if raw.endswith("\r") else raw
        if not program:
            # a here-document that writes a program: NAME, its end word, its first line
            if here is not None and re.sub(r"^> ?", "", line).strip() == here[1]:
                here = None
            m = HEREDOC.search(line) if here is None else None
            if m:
                w = WRITES.search(line)
                if w:
                    here = (os.path.basename(w.group(1)), m.group(1), i)
            elif here is not None and (LINE.match(line) or SHOWN.match(line)):
                written.append((len(out), here[0], i - here[2]))
        if in_snap:
            if line.startswith("#"):
                removed.append(i)
                continue
            in_snap = False
        if snap and SNAP.match(line):
            removed.append(i)
            in_snap = True
            continue
        if LINE.match(line) or (not program and (SHOWN.match(line) or AWK_PRINT.match(line))):
            removed.append(i)
            continue
        new, n = IN_STRING.subn("", raw)
        strings += n
        if n and not program:
            # `printf '...' > NAME`: the line's number in NAME is one more
            # than the newlines written before it
            w = WRITES.search(raw)
            m = IN_STRING.search(raw)
            if w and m:
                written.append((len(out) + 1, os.path.basename(w.group(1)), raw[:m.start()].count("\\n") + 1))
        out.append(new)
    return "\n".join(out), removed, strings, written


class Moves:
    """The lines removed from each file whose later lines moved."""

    def __init__(self):
        self.removed = {}

    def add(self, path, removed, total):
        # a line removed from the end moves nothing
        last = total
        tail = set()
        for r in sorted(removed, reverse=True):
            if r == last:
                tail.add(r)
                last -= 1
        inner = [r for r in removed if r not in tail]
        if inner:
            self.removed[path] = sorted(inner)

    def shift(self, path, n):
        return n - sum(1 for r in self.removed.get(path, ()) if r < n)

    def moved(self, path):
        return path in self.removed


def resolve(name, source, extra_dirs, files):
    """The tracked file NAME means when SOURCE says it, or None."""
    d = os.path.dirname(source)
    stem = os.path.join(d, os.path.basename(source).rsplit(".", 1)[0])
    for base in [d, stem, os.path.dirname(d)] + extra_dirs + [""]:
        cand = os.path.normpath(os.path.join(base, name))
        if cand in files:
            return cand
    if name == os.path.basename(source):
        return source
    return None


def move_positions(path, text, moves, files, written=()):
    """(the text with the positions after a removed line moved, how many).
    `written`: strip_text's, the files this text writes itself."""
    own = path if moves.moved(path) else None
    extra = [os.path.dirname(m) for m in SOURCE.findall(text)]
    if own is None and extra:
        # a .test case: the program is its SOURCE
        for m in SOURCE.findall(text):
            if moves.moved(m):
                own = m
    count = [0]

    def target(name):
        t = resolve(name, path, extra, files)
        return t if t is not None and moves.moved(t) else None

    def num(t, s):
        n = int(s)
        m = moves.shift(t, n)
        if m != n:
            count[0] += 1
        return str(m)

    cur = [0]
    # the files the text writes itself (`printf ... > main.vl`, `cat >
    # main.vl <<EOF`): below that line a position in one is of what was
    # written, not of the tracked file of that name
    rewritten = {}
    for k, line in enumerate(text.split("\n")):
        if ("printf" in line or "<<" in line or "echo " in line) and line.lstrip()[:1] in ("%", "$"):
            w = WRITES.search(line)
            if w:
                rewritten.setdefault(os.path.basename(w.group(1)), []).append(k)

    def last_write(name):
        # the line of the last write of name above this one, or -1
        return max([k for k in rewritten.get(os.path.basename(name), ()) if k < cur[0]], default=-1)

    def own_text(name):
        return last_write(name) >= 0

    def local(name, s):
        # a file the text wrote above this line, with a line removed
        n = int(s)
        base = os.path.basename(name)
        since = last_write(name)
        k = sum(1 for at, b, v in written if b == base and since < at <= cur[0] and v < n)
        if k:
            count[0] += 1
        return str(n - k)

    def file_pos(m):
        t = None if own_text(m.group(1)) else target(m.group(1))
        if t is None:
            if not written:
                return m.group(0)
            s = m.group(1) + ":" + local(m.group(1), m.group(2))
            if m.group(3) is not None:
                s += "-" + local(m.group(1), m.group(3))
            return s
        s = m.group(1) + ":" + num(t, m.group(2))
        if m.group(3) is not None:
            s += "-" + num(t, m.group(3))
        return s

    def file_line(m):
        t = None if own_text(m.group(1)) else target(m.group(1))
        if t is None:
            return m.group(0)
        return m.group(1) + ": line " + num(t, m.group(2))

    bare = [0]

    def own_line(m):
        before = count[0]
        r = "line " + num(own, m.group(1))
        bare[0] += count[0] - before
        return r

    out = []
    for k, line in enumerate(text.split("\n")):
        cur[0] = k
        if ".vl" in line or ".tach" in line:
            line = FILE_POS.sub(file_pos, line)
            line = FILE_LINE.sub(file_line, line)
        if own is not None:
            d = DIRECTIVE.match(line)
            if d:
                key = d.group(1)
                head, body = line[:d.end()], line[d.end():]
                body = BARE_LINE_COL.sub(own_line, body)
                if key in ("ERROR", "WARNING"):
                    cut = body.find("output: ")
                    if cut < 0:
                        body = BARE_LINE.sub(own_line, body)
                    body = AT_POS.sub(lambda m: "at " + num(own, m.group(1)), body)
                elif key.startswith("XFAIL"):
                    cut = re.search(r"(?:^|[;:] )rust ", body)
                    if cut:
                        body = body[:cut.end()] + CODE_POS.sub(lambda m: "@" + num(own, m.group(1)), body[cut.end():])
                line = head + body
        out.append(line)
    return "\n".join(out), count[0], bare[0]


def table(title, counts, unit):
    if not counts:
        return
    print(title)
    for g in sorted(counts):
        files, n = counts[g]
        print("  %-28s %5d files, %6d %s" % (g, files, n, unit))
    print("  %-28s %5d files, %6d %s" % ("total", sum(c[0] for c in counts.values()),
                                          sum(c[1] for c in counts.values()), unit))


def bump(counts, path, n):
    c = counts.setdefault(group(path), [0, 0])
    c[0] += 1
    c[1] += n


def strip(argv):
    dry = False
    listing = False
    keep = list(KEEP)
    only = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--dry-run":
            dry = True
        elif a == "--list":
            listing = True
        elif a == "--keep" and i + 1 < len(argv):
            keep.append(argv[i + 1])
            i += 1
        elif a.startswith("-"):
            sys.stderr.write(__doc__)
            return 2
        else:
            p = os.path.relpath(os.path.abspath(a), ROOT)
            only.append(p + "/" if os.path.isdir(os.path.join(ROOT, p)) and not p.endswith("/") else p)
        i += 1

    paths = tracked()
    files = set(paths)
    texts = {}
    moves = Moves()
    new_text = {}
    removed_by = {}
    strings_by = {}
    written_by = {}
    kept = []
    for p in paths:
        if under(p, HISTORY):
            continue
        t = read(p)
        if t is None:
            continue
        texts[p] = t
        if TEXT not in t:
            continue
        if under(p, keep):
            if any(LINE.match(l.rstrip("\r")) for l in t.split("\n")) or IN_STRING.search(t):
                kept.append(p)
            continue
        if only and not under(p, only):
            continue
        stripped, removed, strings, written = strip_text(p, t)
        if not removed and not strings:
            continue
        if written:
            written_by[p] = written
        total = len(t.split("\n")) - (1 if t.endswith("\n") else 0)
        new_text[p] = stripped
        removed_by[p] = removed
        strings_by[p] = strings
        moves.add(p, removed, total)

    lines_c = {}
    strings_c = {}
    for p in sorted(removed_by):
        if removed_by[p]:
            bump(lines_c, p, len(removed_by[p]))
        if strings_by[p]:
            bump(strings_c, p, strings_by[p])

    moved_c = {}
    moved_files = []
    ambiguous = []
    by_dir = {}
    for q in paths:
        parts = q.split("/")
        for k in range(1, len(parts)):
            by_dir.setdefault("/".join(parts[:k]), []).append(q)
    for p in paths:
        if p not in texts or under(p, keep):
            continue
        t = new_text.get(p, texts[p])
        if not moves.removed and p not in written_by:
            continue
        m, n, bare = move_positions(p, t, moves, files, written_by.get(p, ()))
        if n:
            new_text[p] = m
            bump(moved_c, p, n)
            moved_files.append((p, n))
        # a position with no file name in a program of several files: it
        # was moved as the root's, and may be a module's
        d = os.path.dirname(p)
        if bare and os.path.basename(p) == "main.vl" and any(q != p and q.endswith(".vl") and os.path.dirname(q).startswith(d) and not moves.moved(q)
                        for q in by_dir.get(d, ())):
            ambiguous.append("%s (%d positions without a file name)" % (p, bare))

    if not dry:
        for p in sorted(new_text):
            write(p, new_text[p])

    print("strip-edition:%s %d files changed" % (" (dry run)" if dry else "", len(new_text)))
    table("edition lines removed, by directory:", lines_c, "lines")
    table("edition lines removed from strings (`...\\n`), by directory:", strings_c, "strings")
    table("positions moved, by directory:", moved_c, "positions")
    if listing:
        for p in sorted(new_text):
            print("changed\t%s\t%d lines\t%d strings\t%d positions" % (
                p, len(removed_by.get(p, ())), strings_by.get(p, 0), dict(moved_files).get(p, 0)))
    if kept:
        print("kept (the previous release reads them; compiler/src is the compiler's change):")
        for p in kept:
            print("  " + p)

    # what is left, by kind
    hand = []
    uses = []
    prose = {}
    rerecord = set()
    for p in paths:
        if p not in texts or under(p, keep):
            continue
        t = new_text.get(p, texts[p])
        ext = os.path.splitext(p)[1]
        code = ext in CODE_EXT or p.startswith("tools/")
        if TEXT in t or USES.search(t):
            for n, line in enumerate(t.split("\n"), 1):
                if TEXT in line:
                    if code or ext in TRANSCRIPT_EXT:
                        hand.append("%s:%d: %s" % (p, n, line.strip()[:110]))
                    else:
                        prose[p] = prose.get(p, 0) + 1
                elif USES.search(line):
                    uses.append("%s:%d: %s" % (p, n, line.strip()[:110]))
    for p in new_text:
        if p.endswith(TRANSCRIPT_EXT):
            rerecord.add(p)
        # a transcript's program: tests/query/NAME/..., tests/refactor/NAME/..., tests/lsp/prog*/
        parts = p.split("/")
        if len(parts) > 3 and parts[0] == "tests" and parts[1] in ("query", "refactor"):
            for e in (".q", ".t"):
                c = "/".join(parts[:2]) + "/" + parts[2] + e
                if c in files:
                    rerecord.add(c)
            if parts[2] == "inputs":
                rerecord.add("/".join(parts[:2]) + "/*.t that reads inputs/" + "/".join(parts[3:]))
        if len(parts) > 2 and parts[0] == "tests" and parts[1] == "lsp" and not p.endswith(".lsp"):
            rerecord.add("tests/lsp/*.lsp (the sessions' programs and texts changed: tests/lsp/run.sh)")
        if p.endswith("README.md"):
            rerecord.add(p + " (a session: tests/walkthrough/run.sh)")
    if hand:
        print("left for a hand (the line is read or written by this code; %d lines):" % len(hand))
        for h in hand:
            print("  " + h)
    if uses:
        print("--edition and VOLE_EDITION are used here (%d lines):" % len(uses))
        for u in uses:
            print("  " + u)
    if prose:
        print("mentioned in prose (%d files): %s" % (len(prose), " ".join("%s(%d)" % (p, n) for p, n in sorted(prose.items()))))
    if ambiguous:
        print("run these (moved as the root file's; a module without the line may be meant; %d):" % len(ambiguous))
        for a in ambiguous:
            print("  " + a)
    if rerecord:
        print("re-record (run the runner; `-u` where it differs, then --check-rerecord; %d):" % len(rerecord))
        for r in sorted(rerecord):
            print("  " + r)
    if not new_text and not hand and not uses:
        print("strip-edition: nothing to do")
    return 0


def check_rerecord(argv):
    only = [a for a in argv if not a.startswith("-")]
    cmd = ["git", "diff", "--name-only", "HEAD", "--"] + (only or ["."])
    names = subprocess.run(cmd, cwd=ROOT, capture_output=True, check=True).stdout.decode().split("\n")
    bad = 0
    seen = 0

    def norm(text):
        out = []
        for line in text.split("\n"):
            line = IN_STRING.sub("", line)
            if "EDITION: rust" in line:
                continue
            out.append(re.sub(r"\d+", "N", line))
        return out

    for p in names:
        if not p.endswith(TRANSCRIPT_EXT + ("README.md",)):
            continue
        seen += 1
        old = subprocess.run(["git", "show", "HEAD:" + p], cwd=ROOT, capture_output=True).stdout.decode("utf-8", "replace")
        new = read(p) or ""
        a, b = norm(old), norm(new)
        if a != b:
            bad += 1
            k = 0
            while k < min(len(a), len(b)) and a[k] == b[k]:
                k += 1
            print("read by hand\t%s\tfirst difference near line %d: %s" % (p, k + 1, (b[k] if k < len(b) else "(end)")[:100]))
    print("check-rerecord: %d transcripts and sessions changed, %d differ in more than numbers and edition lines" % (seen, bad))
    return 1 if bad else 0


def main(argv):
    if "-h" in argv or "--help" in argv:
        sys.stdout.write(__doc__)
        return 0
    if "--check-rerecord" in argv:
        return check_rerecord([a for a in argv if a != "--check-rerecord"])
    return strip(argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
