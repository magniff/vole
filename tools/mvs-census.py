#!/usr/bin/env python3
"""What in the tree is still the old edition's, or still names an edition
(0.28.0: the measure of "no MVS left"; after the strip, tools/strip-edition.py).

usage: tools/mvs-census.py [--allow FILE] [--no-allow] [--summary] [--owners]

Prints one line per entry, `OWNER<TAB>CLASS<TAB>PATH[<TAB>note]`, then the
counts, and exits 1 when an entry is left that the allow-list does not
cover (0 otherwise). The gate runs it with `--no-allow` (the mvs-census
row): `census: 0 entries, 0 allowed, 0 left`.

There is one edition and no file names it, so no file is read as MVS: the
compiler refuses MVS's spellings in every program the suite builds. What
the suite does not build, and what still speaks of editions, is counted:
  edition-line  a file with a line `// EDITION: ...` (alone on a line, or
                written by a script: `...// EDITION: rust\n...`), outside
                what the previous release reads (KEEP_LINE) and the
                records of earlier releases (HISTORY)
  edition-flag  a file that uses `--edition` or VOLE_EDITION (not rustc's
                own `--edition 2021`), outside the compiler's parsing of
                it, the test that it is refused and the rows that give it
                to the previous release (KEEP_FLAG), and HISTORY
  old-std       a file that uses VOLE_STD2 (there is one std)
  std           a file of compiler/std2 (std2 is compiler/std), or of
                compiler/std while compiler/std2 is still there (the old
                std)
  program       a .vl text no compiler run reads on its own (no `fn main`,
                or under inputs/ or texts/: a text a test feeds to `edit`,
                a module a step adds) that uses MVS's words (`var`,
                `inout`, `sink`, `defer`, `self: *T`, a `[T]` parameter or
                result)
  generator     a script (.awk, .sh, .py, .pl) that writes vole programs
                and has MVS's words in what it writes; its programs are
                not in the tree, so no other class sees them
  guide, book, mvs-block
                a topic or chapter outside the runners' RUST_TOPICS and
                RUST_CHAPTERS lists, a block marked `mvs`: none once the
                runners have no such lists

The allow-list (default tools/mvs-census.allow, gone with 0.28.0) has one
path or path prefix per line (`#` comments; a prefix ends with `/`; `*` in
a line: a glob of the whole path).

Owners: d6 (the edition's line and flag), d4 (the old std, VOLE_STD2),
mig28, gpu, del280 as before, other.
"""
import fnmatch
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EDITION = re.compile(r"^// EDITION: \w+\s*$|// EDITION: \w+(?:\\r)?\\n", re.M)
EDITION_USE = re.compile(r"--edition\b|\bVOLE_EDITION\b")
# rustc's own option (the twins): `--edition 2021`, `"--edition", edition`
RUSTC_EDITION = re.compile(r"rustc|RUSTC|--edition[\"', =]+(?:20\d\d|edition\b|\"\$\{redition)")
STD2_USE = re.compile(r"\bVOLE_STD2\b")
# What the previous release reads (0.27.8 takes the edition of what it
# builds from the line: compiler/src, and tests/compile_cost.sh's programs),
# and the case that the line is a comment now.
KEEP_LINE = ("compiler/src/main.vl", "tests/cost/", "tests/compile_cost.sh", "tests/run/edition_line_comment.vl")
# The compiler's reading of the option (accepted and ignored for one
# release, `mvs` refused; the code cache's key knows its spelling), the
# transcript and the case of that, the two documents that say it is
# deprecated, and the two scripts that give the option to the previous
# release.
KEEP_FLAG = ("compiler/src/main.vl", "compiler/src/front/rust/mod.vl", "compiler/src/cli/build.vl",
             "compiler/src/back/codecache/mod.vl", "tests/refactor/envedition.t",
             "tests/run/edition_flag_ignored.vl", "AGENTS.md", "docs/grammar.md",
             "tests/compile_cost.sh", "bench/run.sh")
# The records of earlier releases, and the census's and the strip's own files.
HISTORY = ("docs/releases.md", "docs/roadmap.md", "docs/design/", "bootstrap/releases.toml", "feedbacks/",
           "editors/vscode/CHANGELOG.md", "tools/mvs-census", "tools/strip-edition.py",
           "tools/test-strip-edition.py", ".claude/")
MOD = re.compile(r"(?:^|[;{}])\s*(?:pub(?:\([a-z]+\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*;", re.M)
# MVS's words, for a text no root reaches
MVS_WORDS = re.compile(
    r"^\s*(?:pub\s+)?(?:static\s+)?var\s+[a-z_]|\b(?:inout|sink)\s+[A-Za-z_&*\[(]|^\s*defer\s|\bself:\s*\*"
    r"|[(,]\s*[a-z_][a-z0-9_]*:\s*\[[A-Za-z0-9_]+\]\s*[,)]|\)\s*->\s*\[[A-Za-z0-9_]+\]\s*\{", re.M)
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
    if path.startswith(("tests/refactor/stdedit/", "tests/query/stdpos0253/",
                        "tests/refactor/inputs/strip_prefix")):
        return "d4"
    if path.startswith(("tests/gpu/", "tests/window/", "tests/voltty-render/", "tools/objcgen/", "tools/wgslc/", "bench/gpu/shader/run.sh")):
        return "gpu"
    if top[0] in ("book", "examples", "bench", "editors") or path.startswith("compiler/guide/") or path == "README.md":
        return "mig28"
    if path.startswith("tools/numtables/"):
        return "d4"
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


def under(path, prefixes):
    return any(path == p or path.startswith(p) for p in prefixes)


def programs(paths):
    files = {p for p in paths if p.endswith(".vl")}
    text = {p: read(p) for p in files}
    kids = {p: children(p, text[p], files) for p in files}
    is_child = {c for p in files for c in kids[p] if c != p}
    old_std = any(p.startswith("compiler/std2/") for p in paths)
    entries = []
    for p in sorted(files):
        if p.startswith("compiler/std2/"):
            entries.append(("std", p, "std2 is compiler/std"))
            continue
        if old_std and p.startswith("compiler/std/"):
            entries.append(("std", p, ""))
            continue
        parts = p.split("/")
        if p not in is_child and ("inputs" in parts or "texts" in parts or not MAIN.search(text[p])):
            # a text fed to an edit, a module a step adds, a file left out
            # on purpose (no `fn main`): no run reads it alone
            if MVS_WORDS.search(text[p]):
                entries.append(("program", p, "text"))
    return entries


def marks(paths):
    """The files that still name an edition or the second std."""
    entries = []
    for p in sorted(paths):
        if under(p, HISTORY):
            continue
        try:
            t = read(p)
        except (OSError, UnicodeDecodeError):
            continue
        if "EDITION" not in t and "--edition" not in t and "VOLE_STD2" not in t:
            continue
        lines = t.split("\n")
        if not under(p, KEEP_LINE):
            hits = [i for i, line in enumerate(lines, 1) if EDITION.search(line)]
            if hits:
                entries.append(("edition-line", p, "line %d, %d lines" % (hits[0], len(hits))))
        if not under(p, KEEP_FLAG):
            hits = [i for i, line in enumerate(lines, 1) if EDITION_USE.search(line) and not RUSTC_EDITION.search(line)]
            if hits:
                entries.append(("edition-flag", p, "line %d, %d lines" % (hits[0], len(hits))))
        hits = [i for i, line in enumerate(lines, 1) if STD2_USE.search(line)]
        if hits:
            entries.append(("old-std", p, "line %d, %d lines" % (hits[0], len(hits))))
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
    entries = programs(paths) + marks(paths) + generators(paths) + docs(paths)
    allow = load_allow(allow_file)
    counts = {}
    dirs = {}
    left = 0
    for cls, p, note in entries:
        ok = allowed(p, allow)
        o = "d4" if cls in ("std", "old-std") else "d6" if cls.startswith("edition-") else owner(p)
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
