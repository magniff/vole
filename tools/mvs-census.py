#!/usr/bin/env python3
"""What in the tree is still read as MVS (0.28.0: the measure of "no MVS left").

usage: tools/mvs-census.py [--allow FILE] [--no-allow] [--summary] [--owners]

Prints one line per entry, `OWNER<TAB>CLASS<TAB>PATH[<TAB>note]`, then the
counts, and exits 1 when an entry is left that the allow-list does not
cover (0 otherwise). The gate runs it with `--no-allow`.

An entry is:
  program   a .vl file a compiler run reads in the MVS edition: a root (a
            file no other file of its tree names with `mod NAME;`) without
            a line `// EDITION: rust` or `// FLAGS: ... --edition rust`,
            and every module file reached only from such roots

  generator a script (.awk, .sh, .py, .pl) that writes vole programs and
            has MVS's words in what it writes (tests/fuzz/gen.awk); its
            programs are not in the tree, so no other class sees them

  guide     a topic of compiler/guide with code blocks that is not in
            tests/guide/run.sh's RUST_TOPICS
  book      a chapter of book/ with code blocks that is not in
            tests/book/run.sh's RUST_CHAPTERS
  mvs-block a block or session marked `mvs` in a rust chapter (PATH:LINE)

A module file is the rust edition's when one rust root reaches it; a file
no root reaches is its own root. One without a `fn main`, or under inputs/
or texts/ (a text a test feeds to `edit`, a module a step adds, a file
left out on purpose), is read with the program it is put into: it is
listed only when it uses MVS's words (`var`, `inout`, `sink`, `defer`,
`self: *T`, a `[T]` parameter or result, `.len` without a call, `*T`).

The allow-list (default tools/mvs-census.allow) has one path or path
prefix per line (`#` comments; a prefix ends with `/`); an entry under it
is counted as allowed and does not fail the run (`*` in a line: a glob
of the whole path).

Owners: mig28 (book, examples, guide, bench, the editor samples), gpu
(the gpu port: tests/gpu, window, voltty-render, two tools), del280 (the
other tests), other (anything else).
"""
import fnmatch
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EDITION = re.compile(r"^// EDITION: rust\s*$", re.M)
FLAGS = re.compile(r"^// FLAGS:.*--edition[= ]rust", re.M)

MOD = re.compile(r"(?:^|[;{}])\s*(?:pub(?:\([a-z]+\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*;", re.M)
# MVS's words, for a text no root reaches
MVS_WORDS = re.compile(
    r"^\s*(?:pub\s+)?(?:static\s+)?var\s+[a-z_]|\b(?:inout|sink)\s+[A-Za-z_&*\[(]|^\s*defer\s|\bself:\s*\*"
    r"|[(,]\s*[a-z_][a-z0-9_]*:\s*\[[A-Za-z0-9_]+\]\s*[,)]|\)\s*->\s*\[[A-Za-z0-9_]+\]\s*\{|(?<=[A-Za-z0-9_\])])\.len\b(?!\s*\()"
    r"|:\s*\*(?!const\b|mut\b)[A-Za-z]", re.M)
MAIN = re.compile(r"\bfn\s+main\s*\(")
# A script that writes vole programs (a generator: tests/arch/gen.awk,
# the fuzzers): its text has a `fn NAME(` and MVS's words, wherever they
# stand in a line (inside a string, after a quote)
GEN_EXT = (".awk", ".sh", ".py", ".pl")
GEN_FN = re.compile(r"\bfn\s+[a-z_][a-z0-9_]*\s*(?:<[^>]*>)?\(")
GEN_WORDS = re.compile(
    r"\bvar\s+[a-z_][a-z0-9_]*\s*(?::\s*[A-Za-z\[(&*]|=[^=])|\b(?:inout|sink)\s+[A-Za-z_&*\[(]|\bself:\s*\*"
    r"|[(,]\s*[a-z_][a-z0-9_]*:\s*\[[A-Za-z0-9_]+\]\s*[,)]|\)\s*->\s*\[[A-Za-z0-9_]+\]\s*\{"
    r"|[a-z_\])]\.len\b(?!\s*\()|[a-z_]:\s*\*(?!const\b|mut\b)[A-Za-z*]")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def tracked():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [p for p in out.decode().split("\0") if p and os.path.isfile(os.path.join(ROOT, p))]


def owner(path):
    top = path.split("/")

    if path.startswith(("tests/gpu/", "tests/window/", "tests/voltty-render/", "tools/objcgen/", "tools/wgslc/", "bench/gpu/shader/run.sh")):
        return "gpu"
    if top[0] in ("book", "examples", "bench", "editors") or path.startswith("compiler/guide/") or path == "README.md":
        return "mig28"

    if path.startswith("tools/agent-hooks/") or top[0] == "tests":
        return "del280"
    return "other"


def children(path, text, files):
    """The module files `path` names with `mod NAME;`."""
    d, base = os.path.split(path)
    dirs = [d]
    if base != "mod.vl":
        dirs.append(os.path.join(d, base[:-3]))
    found = []
    for name in MOD.findall(text):
        for dd in dirs:
            for cand in (os.path.join(dd, name + ".vl"), os.path.join(dd, name, "mod.vl")):
                if cand in files:
                    found.append(cand)
    return found


def shell_list(path, name):
    m = re.search(r'^%s="([^"]*)"' % name, read(path), re.M)
    return set(m.group(1).split()) if m else None


def programs(paths):
    files = {p for p in paths if p.endswith(".vl")}
    text = {p: read(p) for p in files}
    kids = {p: children(p, text[p], files) for p in files}
    is_child = {c for p in files for c in kids[p] if c != p}
    rust = set()
    old_std = []

    def mark(p, into):
        stack = [p]
        while stack:
            q = stack.pop()
            if q in into:
                continue
            into.add(q)
            stack.extend(kids[q])

    roots = sorted(files - is_child)
    for r in roots:
        if EDITION.search(text[r]) or FLAGS.search(text[r]):
            mark(r, rust)
    # a module file with its own rust line (std2's files, a test's module)
    for p in files:
        if EDITION.search(text[p]):
            mark(p, rust)
    mvs = set()
    for r in roots:
        if r not in rust:
            mark(r, mvs)
    mvs -= rust
    entries = []
    for p in sorted(mvs):

        parts = p.split("/")
        if p in roots and ("inputs" in parts or "texts" in parts or not MAIN.search(text[p])):
            # a text fed to an edit, a module a step adds, a file left out
            # on purpose (no `fn main`): MVS only by its words
            if MVS_WORDS.search(text[p]):
                entries.append(("program", p, "text"))
            continue
        entries.append(("program", p, "root" if p in roots else "module"))
    for r in old_std:
        entries.append(("old-std", r, ""))
    return entries


def generators(paths):
    """The scripts that write MVS programs: (class, path, the first MVS
    word and how many lines have one). The census's own files are not generators."""
    entries = []
    for p in sorted(paths):
        if not p.endswith(GEN_EXT) or p.startswith(("tools/mvs-census", ".claude/")):
            continue
        # tests/seed-compat.awk rewrites a program into the bootstrap
        # seed's dialect (the gate's fuzz-seed row): the `*u8` and `var`
        # in it are the seed's spellings and the ones it replaces, not
        # MVS written into a program the compiler reads.
        if p == "tests/seed-compat.awk":
            continue
        # bench/gpu/shader/run.sh writes a WGSL shader (large.wgsl): the
        # `fn` and `var` in it are WGSL's.
        if p == "bench/gpu/shader/run.sh":
            continue
        text = read(p)
        if not GEN_FN.search(text):
            continue
        hits = [(i, m.group(0).strip()) for i, line in enumerate(text.split("\n"), 1)
                for m in [GEN_WORDS.search(line)] if m]
        if hits:
            entries.append(("generator", p, "line %d `%s`, %d lines" % (hits[0][0], hits[0][1][:24], len(hits))))
    return entries


def fences(path):
    """(line, info) of each fence that opens a block."""
    out = []
    inside = False
    for i, line in enumerate(read(path).split("\n"), 1):
        if line.startswith("```"):
            if not inside:
                out.append((i, line[3:].strip()))
            inside = not inside
    return out


def is_code(info):
    w = info.split()
    return bool(w) and w[0] in ("vole", "tach", "console")


def docs(paths):
    entries = []
    topics = shell_list("tests/guide/run.sh", "RUST_TOPICS")
    chapters = shell_list("tests/book/run.sh", "RUST_CHAPTERS")
    for p in sorted(paths):
        if p.startswith("compiler/guide/") and p.endswith(".md"):
            n = sum(1 for _, info in fences(p) if is_code(info))
            topic = os.path.basename(p)[:-3]
            if n and topics is not None and topic not in topics:
                entries.append(("guide", p, "%d blocks" % n))
        elif p.startswith("book/") and p.endswith(".md"):
            fs = [(ln, info) for ln, info in fences(p) if is_code(info)]
            num = os.path.basename(p).split("-")[0]
            if not fs or chapters is None:
                continue
            if num not in chapters:
                entries.append(("book", p, "%d blocks" % len(fs)))
            else:
                for ln, info in fs:
                    if "mvs" in info.split()[1:]:
                        entries.append(("mvs-block", "%s:%d" % (p, ln), info))
    return entries


def load_allow(path):
    out = []
    if path and os.path.isfile(path):
        for line in open(path, encoding="utf-8"):
            line = line.split("#")[0].strip()
            if line:
                out.append(line)
    return out


def allowed(path, allow):
    bare = path.split(":")[0]
    for a in allow:
        if bare == a or path == a or (a.endswith("/") and bare.startswith(a)) or ("*" in a and fnmatch.fnmatch(bare, a)):
            return True
    return False


def main(argv):
    allow_file = os.path.join(ROOT, "tools/mvs-census.allow")
    summary = False
    by_dir = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--allow" and i + 1 < len(argv):
            allow_file = argv[i + 1]
            i += 1
        elif a == "--no-allow":
            allow_file = None
        elif a == "--summary":
            summary = True
        elif a == "--owners":
            summary = True
            by_dir = True
        else:
            sys.stderr.write(__doc__)
            return 2
        i += 1
    paths = tracked()
    entries = programs(paths) + generators(paths) + docs(paths)
    allow = load_allow(allow_file)
    counts = {}
    dirs = {}
    left = 0
    for cls, p, note in entries:
        ok = allowed(p, allow)
        o = owner(p)
        key = (o, cls)
        c = counts.setdefault(key, [0, 0])
        c[0] += 1
        if ok:
            c[1] += 1
        else:
            left += 1
        parts = p.split("/")
        d = "/".join(parts[:2]) if parts[0] in ("tests", "compiler", "examples") and len(parts) > 2 else parts[0]
        dirs[(o, d)] = dirs.get((o, d), 0) + 1
        if not summary:
            print("%s\t%s\t%s%s%s" % (o, cls, p, "\t" + note if note else "", "\tallowed" if ok else ""))
    if by_dir:
        for (o, d), n in sorted(dirs.items()):
            print("%s\t%s\t%d" % (o, d, n))
    for (o, cls), (n, ok) in sorted(counts.items()):
        print("census: %s %s: %d%s" % (o, cls, n, " (%d allowed)" % ok if ok else ""))
    print("census: %d entries, %d allowed, %d left" % (len(entries), len(entries) - left, left))
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
