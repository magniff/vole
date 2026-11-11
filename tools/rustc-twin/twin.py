"""The rustc twin (0.27.3, plan-0271 §2.2): a rust-edition vole program
turned into Rust, built by stable rustc with the shim's prelude
(tools/rustc-twin/prelude.rs) and run. Used by tools/rustc-twin.sh (cases
with EXPECT lines).

The text's changes, all the shim does not do as Rust items:
  - main: `fn main(gpa: Gpa) -> i32` becomes `fn vole_twin_main(..)`,
    called by a Rust `main` that passes `Gpa` and exits with its result;
  - the allocator argument of a type: `, Gpa>` and `<Gpa>`, `::<Gpa>`
    dropped (`Vec<T, Gpa>` -> `Vec<T>`, `String<Gpa>` -> `String`);
  - `use` of the prelude's names (Gpa, Allocator, ToStringIn, CollectIn,
    DefaultIn, CloneIn, FromIteratorIn, ToOwnedIn, ...) dropped;
  - the format functions to Rust's macros: `println(..)` -> `println!(..)`
    (print, eprint, eprintln, format_args, write, writeln, panic, assert,
    assert_eq, assert_ne, todo, unreachable, unimplemented; a first
    argument that is no literal is printed: `println(s)` -> `println!("{}",
    s)`), `format_in(.., gpa)` -> `format!(..)`;
  - any other `X_in(.., gpa)` the prelude does not serve (a free function:
    `io::read_to_string_in(r, gpa)`, `thread::spawn_in(f, gpa)`) -> `X(..)`.
The prelude is appended, so the program's lines keep their numbers.

A program is `outside` the twin when vole-only items are left (Arena,
Formatter::new, an allocator generic, ...), when rustc rejects the text,
or when the case says `// RUSTC: none WHY`.
"""
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
PRELUDE = open(os.path.join(HERE, "prelude.rs")).read()
# (--alloc-api: Rust's own allocator_api, rustc as nightly)
PRELUDE_ALLOC = open(os.path.join(HERE, "prelude_alloc.rs")).read()

MACROS = ["println", "print", "eprintln", "eprint", "format_args", "write", "writeln",
          "panic", "assert", "assert_eq", "assert_ne", "debug_assert", "todo",
          "unimplemented", "unreachable"]
# where the format string is
FMT_ARG = {"write": 1, "writeln": 1, "assert": 1, "debug_assert": 1, "assert_eq": 2, "assert_ne": 2}
# the `_in` names the prelude serves as methods or associated functions
SERVED = {"new_in", "with_capacity_in", "with_hasher_in", "with_capacity_and_hasher_in",
          "from_in", "default_in", "from_iter_in", "to_string_in", "clone_in", "to_owned_in",
          "collect_in", "unzip_in", "partition_in", "to_vec_in", "repeat_in", "sort_in",
          "sort_by_in", "sort_by_key_in", "to_uppercase_in", "to_lowercase_in",
          "to_ascii_uppercase_in", "to_ascii_lowercase_in", "replace_in", "replacen_in",
          "lines_in"}
PRELUDE_NAMES = {"Gpa", "Allocator", "ToStringIn", "CollectIn", "DefaultIn", "CloneIn",
                 "FromIteratorIn", "ToOwnedIn", "FromIn", "NewIn", "WithCapacityIn"}
# left after the changes: the program is outside
VOLE_ONLY = [r"\bArena\b", r"\bAnyAlloc\b", r"\bFixedBuf\b", r"Formatter::new\b",
             r"(?<![.\w])allocator\(\)", r"\blive_blocks\b", r"\bcheck_leaks\b", r"\bFixedState\b",
             r"\bFoldHasher\b", r"#\[array_builtin", r"\bTypedArena\b", r"\bArenaScope\b",
             r"\barena_scope\b", r"\bAllocator for\b", r"\bAllocator\b", r"\bdetect\(", r"#\[multiversion",
             r"\bstd::(gpu|window|objc|arch|term)\b", r"\bextern \"C\"", r"\bimport\s+\"",
             r"(?m)^\s*(requires|ensures)\b", r"\bbuiltin_impls\b"]
# vole's static checks, which change nothing at run time: dropped
CHECK_ATTRS = r"(?m)^[ \t]*#\[(effects\([^)]*\)|pure|no_alloc|no_panic|total)\][ \t]*$"


# (the cases' directives and their stdout's comparison, tests/run.sh's)
def directives(path):
    """tests/directives.awk's reading: a `//` line's KEY: VALUE."""
    d = {"expect": [], "stdin": [], "env": [], "stderr": [], "csource": [], "flags": [],
         "exit": 0, "timeout": 1, "has": set()}
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return d
    for line in text.split("\n"):
        line = line.rstrip("\r").lstrip(" \t")
        if not line.startswith("//"):
            continue
        c = line[2:]
        if c.startswith(" "):
            c = c[1:]
        i = c.find(":")
        if i < 0:
            continue
        key, value = c[:i], c[i + 1:]
        if value.startswith(" "):
            value = value[1:]
        d["has"].add(key)
        if key == "EXPECT":
            d["expect"].append(value)
        elif key == "STDIN":
            d["stdin"].append(value)
        elif key == "ENV":
            d["env"].append(value)
        elif key == "STDERR":
            d["stderr"].append(value)
        elif key == "EXIT":
            d["exit"] = int(value.split()[0]) if value.split() else 0
        elif key == "CSOURCE":
            d["csource"] += value.split()
        elif key == "FLAGS":
            d["flags"] += value.split()
        elif key in ("ARGS", "SOURCE", "CHEADER", "EDITION"):
            d[key.lower()] = value.strip() if key != "ARGS" else value
        elif key == "TIMEOUT":
            try:
                d["timeout"] = max(1, int(value.split()[0]))
            except (ValueError, IndexError):
                pass
    return d


def trimmed(text):
    return re.sub(r"[ \t\r\n]+$", "", text)


NUM = r"[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?"


def same_line(want, got):
    if want == got:
        return True
    if "{num}" not in want and "{int}" not in want and "{..}" not in want:
        return False
    rx = ""
    for part in re.split(r"(\{num\}|\{int\}|\{\.\.\})", want):
        rx += {"{num}": NUM, "{int}": r"[-+]?[0-9]+", "{..}": r".*"}.get(part, re.escape(part))
    return re.fullmatch(rx, got, re.S) is not None


def stdout_differs(want, got):
    """tests/expect.awk's comparison: None, or the first line that differs."""
    want, got = trimmed(want), trimmed(got)
    if want == got:
        return None
    w = want.split("\n") if want else []
    a = got.split("\n") if got else []
    for i in range(max(len(w), len(a))):
        if i >= len(w):
            return f"line {i + 1}: expected the end of the output, got {a[i]!r}"
        if i >= len(a):
            return f"line {i + 1}: expected {w[i]!r}, got the end of the output"
        if not same_line(w[i], a[i]):
            return f"line {i + 1}: expected {w[i]!r}, got {a[i]!r}"
    return None



def scan_args(s, i):
    """s[i] == '(': (the top-level arguments' spans, the index after ')')."""
    depth, j, start, args = 0, i, i + 1, []
    while j < len(s):
        c = s[j]
        if c == '"':
            j += 1
            while j < len(s) and s[j] != '"':
                j += 2 if s[j] == "\\" else 1
        elif c == "'" and re.match(r"'(\\.|[^\\'])+'", s[j:]):
            j += re.match(r"'(\\.|[^\\'])+'", s[j:]).end() - 1
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                if s[start:j].strip():
                    args.append((start, j))
                return args, j + 1
        elif c == "," and depth == 1:
            args.append((start, j))
            start = j + 1
        j += 1
    return None, None


def gpa_names(s):
    """The program's names of a Gpa: `gpa`, and every `NAME: Gpa`."""
    return {"gpa"} | set(re.findall(r"\b([a-z_][a-z0-9_]*)\s*:\s*Gpa\b", s))


def format_in_alloc(s):
    """--alloc-api: `format_in(.., a)` -> `vole_format_in(a, format_args!(..))`."""
    out, pos = [], 0
    for m in re.finditer(r"(?<![\w.:])format_in\(", s):
        if m.start() < pos:
            continue
        args, end = scan_args(s, m.end() - 1)
        if not args or len(args) < 2:
            continue
        kept = [s[a:b].strip() for a, b in args[:-1]]
        alloc = s[args[-1][0]:args[-1][1]].strip()
        out.append(s[pos:m.start()])
        out.append(f"vole_format_in({alloc}, format_args!(" + ", ".join(kept) + "))")
        pos = end
    out.append(s[pos:])
    return "".join(out)


def inverse_in(s, gpas):
    """`format_in(.., gpa)` -> `format!(..)`; an unserved `X_in(.., gpa)` -> `X(..)`."""
    out, pos = [], 0
    for m in re.finditer(r"(?<![\w.])((?:\w+::)*)(\w+)_in(::<[^()]*?>)?\(", s):
        if m.start() < pos:
            continue
        name = m.group(2)
        if name + "_in" in SERVED and name != "format":
            continue
        args, end = scan_args(s, m.end() - 1)
        if args is None or not args or s[args[-1][0]:args[-1][1]].strip() not in gpas:
            continue
        kept = [s[a:b].strip() for a, b in args[:-1]]
        if name == "format":
            call = "format!(" + ", ".join(kept) + ")"
        else:
            call = m.group(1) + name + (m.group(3) or "") + "(" + ", ".join(kept) + ")"
        out.append(s[pos:m.start()])
        out.append(call)
        pos = end
    out.append(s[pos:])
    return "".join(out)


def macros(s):
    """println( -> println!(, a first argument that is no literal printed."""
    # (std2's free `std::fmt::write(w, x)`, which the translator writes
    # qualified (a program's own `write` shadows the prelude's): Rust's is
    # the macro, as for the bare `write(`)
    s = re.sub(r"(?<![\w:])std::fmt::write\(", "write(", s)
    out, pos = [], 0
    pat = re.compile(r"(?<![\w.:!])(" + "|".join(MACROS) + r")\(")
    for m in pat.finditer(s):
        if m.start() < pos or re.search(r"\bfn\s*$", s[max(0, m.start() - 4):m.start()]):
            continue
        name = m.group(1)
        args, end = scan_args(s, m.end() - 1)
        if args is None:
            continue
        parts = [s[a:b].strip() for a, b in args]
        k = FMT_ARG.get(name, 0)
        if len(parts) > k and not parts[k].startswith('"'):
            parts.insert(k, '"{}"')
        out.append(s[pos:m.start()])
        out.append(name + "!(" + ", ".join(parts) + ")")
        pos = end
    out.append(s[pos:])
    return "".join(out)


def drop_uses(line):
    """A `use` of the prelude's names: without them (None: the whole line)."""
    m = re.match(r"(\s*)(pub\s+)?use\s+(.*?)::\{(.*)\};\s*$", line)
    if m:
        keep = [x.strip() for x in m.group(4).split(",")
                if x.strip() and x.strip().split(" as ")[0].strip() not in PRELUDE_NAMES]
        if not keep:
            return None
        return f"{m.group(1)}{m.group(2) or ''}use {m.group(3)}::{{{', '.join(keep)}}};"
    m = re.match(r"\s*(pub\s+)?use\s+.*::(\w+)(\s+as\s+\w+)?;\s*$", line)
    if m and m.group(2) in PRELUDE_NAMES:
        return None
    return line


def main_wrapper(s):
    """vole's main renamed, and a Rust main calling it (None: no main)."""
    m = re.search(r"^fn main\(([^)]*)\)\s*(->\s*([^{]+?))?\s*\{", s, re.M)
    if not m:
        return s, None
    params = m.group(1).strip()
    ret = (m.group(3) or "").strip()
    s = s[:m.start()] + "fn vole_twin_main(" + s[m.start() + len("fn main("):]
    call = "vole_twin_main(" + ("Gpa" if params else "") + ")"
    flush = "std::io::Write::flush(&mut std::io::stdout()).ok();"
    if ret in ("i32", "i64", "u8"):
        w = f"fn main() {{ let c = {call}; {flush} std::process::exit(c as i32) }}"
    elif ret.startswith("Result"):
        w = (f"fn main() {{ let r = {call}; {flush} if r.is_err() {{ "
             f"eprintln!(\"Error: {{:?}}\", r.err().unwrap()); std::process::exit(1) }} }}")
    else:
        w = f"fn main() {{ {call}; }}"
    return s, w


def allocator_generics(s):
    """A generic `N: Allocator` (no user allocator): Gpa, the one there is.

    The parameter leaves its generic list and its where clauses, and every
    other `N` becomes `Gpa` (whose allocator argument is then dropped:
    `Vec<T, N>` -> `Vec<T>`, `fn f(a: N)` -> `fn f(a: Gpa)`)."""
    names = set(re.findall(r"[<,]\s*([A-Z]\w*)\s*:\s*Allocator\b", s))
    names |= set(re.findall(r"\bwhere\b[^{;]*?\b([A-Z]\w*)\s*:\s*Allocator\b", s))
    if not names or re.search(r"\bAllocator\s+for\b", s):
        return s
    bound = r"\s*:\s*Allocator(?:\s*\+\s*[\w:']+)*"
    for n in names:
        s = re.sub(r"<\s*" + n + bound + r"\s*>", "", s)          # <N: Allocator>
        s = re.sub(r"<\s*" + n + bound + r"\s*,\s*", "<", s)      # <N: Allocator, T>
        s = re.sub(r",\s*" + n + bound + r"(?=\s*[,>])", "", s)    # <T, N: Allocator>
        s = re.sub(r"\b" + n + bound + r"\s*,\s*", "", s)         # where N: Allocator, ..
        s = re.sub(r"\bwhere\s+" + n + bound + r"\s*(?=[{;])", "", s)
        s = re.sub(r",\s*" + n + bound + r"\s*(?=[{;])", "", s)    # where .., N: Allocator
        s = re.sub(r"\b" + n + r"\b", "Gpa", s)
    return s


def to_rust(src, alloc_api=False):
    """(the Rust text, None) or (the text so far, why it is outside).
    alloc_api: for Rust's own allocator_api (prelude_alloc.rs): the types
    keep their allocator, and format_in keeps its allocator argument."""
    m = re.search(r"^\s*// RUSTC: none(.*)$", src, re.M)
    if m:
        return src, "RUSTC: none " + (m.group(1).strip() or "(no reason)")
    # (a `use` anywhere in a line: the translator keeps a line's items on it)
    s = re.sub(r"(?<![\w:])(pub\s+)?use\s+[^;{}]*(\{[^{}]*\})?[^;{}]*;",
               lambda m: drop_uses(m.group(0)) or "", src)
    s = re.sub(CHECK_ATTRS, "", s)
    gpas = gpa_names(s)
    if alloc_api:
        while True:
            t = format_in_alloc(s)
            if t == s:
                break
            s = t
    else:
        s = allocator_generics(s)
        s = re.sub(r"::<Gpa>", "", s)
        s = re.sub(r",\s*Gpa\s*>", ">", s)
        s = re.sub(r"<Gpa>", "", s)
        # (0.27.6: a Vec's allocator inferred, rewrite.tsv's Buf::new_in,
        # `Vec::<u8, _>::new_in(gpa)`: `Vec::<u8>::new_in(gpa)`)
        s = re.sub(r"\bVec::<([^<>]*),\s*_\s*>::", r"Vec::<\1>::", s)
    while True:
        t = inverse_in(s, gpas)  # nested calls: the outer one first
        if t == s:
            break
        s = t
    s = macros(s)
    s, wrapper = main_wrapper(s)
    code = re.sub(r"//[^\n]*", "", s)  # (not in a comment, nor a name of its own)
    own = set(re.findall(r"\b(?:struct|enum|union|trait|type|fn)\s+(\w+)", code))
    left = [p for p in VOLE_ONLY if re.search(p, code)
            and not (re.fullmatch(r"\\b(\w+)\\b", p) and p[2:-2] in own)
            and not (alloc_api and p == r"\bAllocator\b")]
    if left:
        return s, "vole-only: " + re.sub(r"\\b|\\", "", left[0])
    if wrapper is None:
        return s, "no fn main"
    return s + "\n" + wrapper + "\n\n" + (PRELUDE_ALLOC if alloc_api else PRELUDE), None


def rust_edition(src):
    """The case's `// RUSTC-EDITION: 2024` (borrowck-twin's), else 2021."""
    m = re.search(r"^\s*// RUSTC-EDITION:\s*(\d+)", src, re.M)
    return m.group(1) if m else "2021"


def rustc_build(rustc, rs, exe, edition="2021", overflow=False, alloc_api=False):
    """None, or the first error line of rustc's. overflow: Rust's overflow
    checks, vole's at -O0 (0.26.3: on at -O0, off at -O1 and -O2).
    alloc_api: rustc as nightly (RUSTC_BOOTSTRAP=1) with
    feature(allocator_api), for prelude_alloc.rs."""
    env = dict(os.environ)
    extra = []
    if alloc_api:
        env["RUSTC_BOOTSTRAP"] = "1"
        extra = ["-Zcrate-attr=feature(allocator_api)"]
    r = subprocess.run([rustc, "--edition", edition, "-A", "warnings", "-C", "opt-level=1",
                        "-C", "overflow-checks=" + ("on" if overflow else "off")] + extra + ["-o", exe, rs],
                       capture_output=True, text=True, env=env)
    if r.returncode == 0:
        return None
    err = r.stderr.split("\n")
    for i, l in enumerate(err):
        if l.startswith("error"):
            at = next((x.strip() for x in err[i + 1:i + 3] if x.strip().startswith("-->")), "")
            return (l + (" " + at.replace("--> ", "at ").rsplit("/", 1)[-1] if at else ""))[:220]
    return "rustc failed"


def find_rustc(given=""):
    if given:
        return given
    for p in os.environ.get("PATH", "").split(os.pathsep):
        if os.access(os.path.join(p, "rustc"), os.X_OK):
            return os.path.join(p, "rustc")
    p = os.path.expanduser("~/.cargo/bin/rustc")
    return p if os.access(p, os.X_OK) else ""


if __name__ == "__main__":
    # `python3 -I twin.py FILE`: the Rust text on stdout; exit 3 and the
    # reason on stderr when the program is outside (tools/borrowck-twin.sh
    # --shim)
    import sys
    rs, why = to_rust(open(sys.argv[-1], encoding="utf-8", errors="replace").read(),
                      alloc_api="--alloc-api" in sys.argv[1:-1])
    if why:
        sys.stderr.write(why + "\n")
        sys.exit(3)
    sys.stdout.write(rs)
