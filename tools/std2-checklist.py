#!/usr/bin/env python3
"""(0.27.0) compiler/std2/checklist.tsv: every item of the rust edition's
std spec tree (compiler/std2), against MVS's std (compiler/std, read
through `volec query items std`).

A line per item: its module, its name (Owner::name for a method), its
kind, its status (kept, renamed, changed or new; gone for the MVS items
compiler/std2/gone.tsv lists), the MVS item it comes from, what the real
check says of it (ok: no error; later: only `edition.later` errors; error:
a plain one), the features it waits for from that check (the
`edition.later` names, and for a plain error the front gap it shows,
GAPS below), the release they give it (`-`: a gap no release has taken),
the features its markers predicted that the check did not report, the
gate-1 test that will cover it, and its signature. Then the counts: per
module, kept, renamed, changed, new and gone; how many items typecheck;
per feature, how many items wait for it.

The check is compiler/std2/typecheck.txt (TYPECHECK below): an error's
item is the one whose lines hold it (an inherent impl's header: each of
its members).
A trait marked `#[builtin_impls(TYPES)]` (its impls for the primitive
types, the compiler's) gets a line of its own for them, `impl Trait for
primitives`, waiting for primitive_builtin.

What feeds it, in an item's comment (and an impl's or trait's, for all its
items):
  // later: NAME, NAME     features (compiler/std2/features.tsv) it waits for
  // mvs: PATH, PATH       the MVS items it replaces (Owner::name or name), when
                           an owner or a name differs (a Vec method now [T]'s)
  // std2: renamed         its name changed (with `// mvs:`)
  // std2: changed: WHY    its meaning or types changed beyond the mapping of
                           std.vl's header (receivers, views, i64 -> usize)
Without a marker, an item whose owner and name MVS's std has is kept, and
any other is new. Some features are seen in the signature itself (char,
FnOnce, SliceIndex, `<X as T>::N`, an impl for `&T`, an assoc const, a
bound on an assoc type). An in-scope MVS item that no line accounts for is
reported, so the diff stays complete. It also checks compiler/std2/rewrite.tsv
(the translator's std table): each row names an MVS item, in four columns.

usage: tools/std2-checklist.py [--volec PATH] [--errors FILE] [--check]
  --errors FILE: rewrite typecheck.txt from FILE, a check's output
  --check: exit 1 when checklist.tsv is not what the tree makes
"""
import os
import re
import subprocess
import sys

TOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TREE = os.path.join(TOP, "compiler", "std2")
OUT = os.path.join(TREE, "checklist.tsv")

# MVS owners and modules in the 0.27.0 brief's scope: an item of theirs that
# no std2 item or gone.tsv line names is reported.
SCOPE_OWNERS = {"Option", "Result", "Vec", "[T]", "str", "String", "Buf", "HashMap", "HashSet", "Iterator",
                "Fmt", "Display", "Debug", "Arena", "ScopedArena", "FixedBuf", "Gpa", "Allocator", "Scope",
                "ScopedJoinHandle", "JoinHandle", "Read", "Write", "BufRead", "BufReader", "BufWriter",
                "Clone", "Default", "Eq", "Ord", "Hash", "Cell", "UnsafeCell", "From", "Into", "TryFrom"}
SCOPE_MODULES = {"std::fmt", "std::io", "std::thread", "std::slice", "std::iter", "std::cell"}
# std2 owner names of MVS's owners that were renamed (for the auto match)
OWNER_ALIASES = {"Formatter": "Fmt", "ArenaScope": "ScopedArena", "Iter": None}


def die(msg):
    print(f"std2-checklist: {msg}", file=sys.stderr)
    sys.exit(2)


def skip_angle(s, i):
    """The index after the balanced <...> starting at s[i] == '<'."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c == "<":
            depth += 1
        elif c == ">" and s[i - 1] != "-":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def strip_generics(t):
    """`Vec<T, A>` -> `Vec`; `&'a Vec<T, A>` -> `&Vec`; `[T]` -> `[T]`;
    `Option<&'a T>` -> `Option<&T>` (an impl on an instantiation keeps it)."""
    t = t.strip()
    t = re.sub(r"'[A-Za-z_]\w*\s*", "", t)
    t = re.sub(r"\bmut\s+", "mut ", t)
    if t.startswith("["):
        return "[T]" if re.match(r"\[\s*\w+\s*\]$", t) else t
    m = re.match(r"(&(?:mut )?)?([\w:]+)", t)
    if not m:
        return t
    base = (m.group(1) or "") + m.group(2).split("::")[-1]
    rest = t[m.end():].strip()
    if rest.startswith("<"):
        inner = rest[1:skip_angle(rest, 0) - 1]
        args = [a.strip() for a in split_top(inner) if a.strip()]
        # generic only when every argument is a bare parameter name
        if args and any(not re.match(r"[A-Z]\w*$", a) for a in args):
            return f"{base}<{', '.join(args)}>"
    return base


def split_top(s):
    out, depth, cur = [], 0, ""
    for c in s:
        if c in "<([":
            depth += 1
        elif c in ">)]":
            depth -= 1
        if c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += c
    if cur.strip():
        out.append(cur)
    return out


def parse_impl_header(h):
    """(trait or None, owner) of `impl<..> Trait<..> for Type<..> where .. {`."""
    h = re.sub(r"^(pub\s+)?(unsafe\s+)?impl", "", h).strip()
    if h.startswith("<"):
        h = h[skip_angle(h, 0):].strip()
    h = re.split(r"\s+where\s+|\s*\{\s*$", h)[0].strip()
    # ` for ` at the top level
    depth, i = 0, 0
    while i < len(h):
        c = h[i]
        if c in "<([":
            depth += 1
        elif c in ">)]" and h[i - 1] != "-":
            depth -= 1
        elif depth == 0 and h.startswith(" for ", i):
            return strip_generics(h[:i]), strip_generics(h[i + 5:]), h[i + 5:].strip()
        i += 1
    return None, strip_generics(h), h


def markers(comment):
    later, mvs, status, why = [], [], None, ""
    for line in comment:
        m = re.match(r"\s*//\s*later:\s*(.*)$", line)
        if m:
            later += [x.strip() for x in m.group(1).split(",") if x.strip()]
        m = re.match(r"\s*//\s*mvs:\s*(.*)$", line)
        if m:
            mvs += [x.strip() for x in m.group(1).split(",") if x.strip()]
        m = re.match(r"\s*//\s*std2:\s*(renamed|changed)(?::\s*(.*))?$", line)
        if m:
            status = m.group(1)
            why = (m.group(2) or "").strip()
    return later, mvs, status, why


def auto_later(sig, in_trait, kind):
    """in_trait: an item of a trait or impl block (an assoc const or type)."""
    t = []
    if re.search(r"\bchar\b", sig):
        t.append("char")
    if "FnOnce" in sig:
        t.append("fn_once")
    if "SliceIndex" in sig:
        t.append("slice_index")
    if re.search(r"<[^<>]*\bas\b[^<>]*>::", sig):
        t.append("qualified_path")
    if kind == "const" and in_trait:
        t.append("assoc_const")
    if kind == "type" and in_trait and re.match(r"\s*type\s+\w+\s*:(?!\s*\?\s*Sized\s*(;|$))", sig):
        t.append("assoc_bounds")
    return t


def module_of(rel):
    parts = rel[:-3].split(os.sep)
    if parts == ["std"]:
        return "std"
    if parts[-1] == "mod":
        parts = parts[:-1]
    return "std::" + "::".join(parts)


def read_tree():
    items = []
    for d, _, fs in os.walk(TREE):
        for f in sorted(fs):
            if f.endswith(".vl"):
                rel = os.path.relpath(os.path.join(d, f), TREE)
                items += read_file(os.path.join(d, f), module_of(rel), rel)
    items.sort(key=lambda it: (it["module"], it["order"]))
    return items


TOP_ITEM = re.compile(r"^pub\s+(?:unsafe\s+)?(fn|struct|enum|trait|type|const|static)\s+(\w+)")
IN_IMPL = re.compile(r"^    pub\s+(?:const\s+)?(?:unsafe\s+)?(fn|const|type)\s+(\w+)")
IN_TRAIT = re.compile(r"^    (?:unsafe\s+)?(fn|type|const)\s+(\w+)")
BLOCK_OPEN = re.compile(r"^(pub\s+)?(unsafe\s+)?(impl\b|trait\b)")
PRIVATE_ITEM = re.compile(r"^(?:unsafe\s+)?(?:fn|struct|enum|union|const|static|type|mod)\s")
PRIVATE_MEMBER = re.compile(r"^    (?:unsafe\s+)?(?:const\s+)?fn\s")
MARKS = {}  # file (relative to compiler/std2) -> its marks


def signature(lines, i):
    """The item's text from line i to its `{` or `;` (several lines joined)."""
    out = []
    for j in range(i, min(i + 12, len(lines))):
        s = lines[j].rstrip()
        out.append(s.strip())
        if s.endswith("{") or s.endswith(";") or s.endswith("}"):
            break
    sig = " ".join(out)
    sig = re.sub(r"\s*\{.*$", "", sig).rstrip(";").strip()
    return sig


def read_file(path, module, rel):
    with open(path) as fh:
        lines = fh.read().split("\n")
    items = []
    # marks: (line, what) in order, what = an item, ("header", members) of an
    # inherent impl, "private" (an item the checklist does not list) or "end"
    marks = []
    comment = []
    derive = False
    builtin = None  # (line, types) of a `#[builtin_impls(..)]` before a trait
    block = None  # dict(kind=trait|impl|traitimpl, owner, trait, later, ...)
    order = 0
    for i, line in enumerate(lines):
        if line.strip().startswith("//"):
            comment.append(line)
            continue
        if line.strip().startswith("#["):
            if line.strip().startswith("#[derive("):
                derive = True
            m = re.match(r"#\[builtin_impls\((.*)\)\]\s*$", line.strip())
            if m:
                builtin = (i + 1, m.group(1).strip())
            continue
        if block is not None and line.startswith("}"):
            block = None
            marks.append((i + 1.5, "end"))
            comment = []
            continue
        if block is None:
            m = BLOCK_OPEN.match(line)
            if m and m.group(3).startswith("impl"):
                header = signature(lines, i)
                trait, owner, owner_text = parse_impl_header(header)
                bl, bm, bs, bw = markers(comment)
                if owner_text.startswith("&"):
                    bl.append("impl_for_ref")
                bl += auto_later(header, False, "impl")
                block = dict(kind="traitimpl" if trait else "impl", owner=owner, trait=trait, later=bl,
                             members=[], sig=header)
                if trait:
                    order += 1
                    items.append(dict(module=module, owner=owner, name=f"impl {trait}", kind="impl", sig=header,
                                      later=sorted(set(bl + auto_later(header, False, "impl"))), mvs=bm,
                                      status=bs, why=bw, order=order, file=rel, line=i + 1))
                    marks.append((i + 1, items[-1]))
                else:
                    marks.append((i + 1, ("header", block)))
                comment = []
                if line.rstrip().endswith("}"):
                    block = None
                    marks.append((i + 1.5, "end"))
                continue
            m = TOP_ITEM.match(line)
            if m:
                kind, name = m.group(1), m.group(2)
                sig = signature(lines, i)
                bl, bm, bs, bw = markers(comment)
                if derive:
                    bl.append("rust_derives")
                order += 1
                items.append(dict(module=module, owner=None, name=name, kind=kind, sig=sig,
                                  later=sorted(set(bl + auto_later(sig, False, kind))), mvs=bm, status=bs, why=bw,
                                  order=order, file=rel, line=i + 1))
                marks.append((i + 1, items[-1]))
                if kind == "trait" and builtin:
                    # the trait's impls for the primitive types: one line, the compiler's
                    order += 1
                    items.append(dict(module=module, owner=None, name=f"impl {name} for primitives", kind="impl",
                                      sig=f"impl {name} for each of {builtin[1]}", later=[], forced=["primitive_builtin"],
                                      mvs=[], status="new", why="", order=order, file=rel, line=builtin[0]))
                    marks.append((builtin[0], items[-1]))
                builtin = None
                if kind == "trait" and not line.rstrip().endswith("}"):
                    block = dict(kind="trait", owner=name, trait=None, later=bl)
                comment = []
                continue
            if PRIVATE_ITEM.match(line):
                marks.append((i + 1, "private"))
        elif block["kind"] in ("impl", "trait"):
            m = (IN_IMPL if block["kind"] == "impl" else IN_TRAIT).match(line)
            if not m and block["kind"] == "impl" and PRIVATE_MEMBER.match(line):
                marks.append((i + 1, "private"))
            if m:
                kind, name = m.group(1), m.group(2)
                sig = signature(lines, i)
                bl, bm, bs, bw = markers(comment)
                order += 1
                items.append(dict(module=module, owner=block["owner"], name=name, kind=kind, sig=sig,
                                  later=sorted(set(bl + block["later"] +
                                                   auto_later(sig, True, kind))),
                                  mvs=bm, status=bs, why=bw, order=order, file=rel, line=i + 1))
                marks.append((i + 1, items[-1]))
                if block["kind"] == "impl":
                    block["members"].append(items[-1])
        comment = []
        derive = False
    MARKS[rel] = marks
    return items

# compiler/std2/typecheck.txt: the front's errors on the tree, one a line
# (`FILE:L:C: error[KIND] MESSAGE`, its `try:` lines dropped), from
# `volec check --edition rust compiler/std2/std.vl` by a build without
# the 50-error cap (base/diag.vl's MAX_ERRORS); `--errors FILE` reads such
# a run's output and rewrites it.
TYPECHECK = os.path.join(TREE, "typecheck.txt")

# A plain error (not edition.later) -> the front gap it shows, a features.tsv
# name: the first pattern that matches "FILE: error[KIND] MESSAGE" wins.
GAPS = [
    (r"unknown attribute 'builtin_impls'", "primitive_builtin"),
    (r"^<std>.*duplicate method", "std2_root"),
    (r"edition\.std_by_value", "std2_root"),
    (r"duplicate method", "method_name_clash"),
    (r"does not have the signature trait", "generic_trait_multi_impl"),
    (r"takes 1 type argument, got 0", "default_type_param"),
    (r"a function of a generic trait has no default body", "generic_trait_default"),
    (r"impl for unknown type 'char'|^char\.vl:.*cannot infer type parameter 'T' of 'Option'", "char"),
    (r"impl for unknown type 'AnyAlloc'|expected type, got 'unsafe'", "unsafe_fn_ptr"),
    (r"'(Send|Sync)' is not a trait in scope", "auto_trait"),
    (r"required by the bound 'M: Display' of 'panic::panic'", "impl_for_ref"),
    (r"is not implemented for .*required by the bound", "method_where"),
    (r"no method '(copied|cloned)' on type 'Option<", "impl_on_instance"),
    (r"cannot derive 'Default'", "rust_derives"),
    (r"of type '\[\w+; \d+\]' has no", "array_builtin"),
    (r"is a builtin \(size_of", "size_of_name"),
    (r"slicing a (raw )?pointer|expected 'str', got '\[str\]'", "str_slice_self"),
    (r"is a type, not a value", "unit_struct_value"),
    (r"conflicting impls of trait 'IntoIterator'", "impl_for_ref"),
    (r"unresolved import 'adapters::Flatten'|got '<<'|expected type, got '<'", "qualified_path"),
    (r"unresolved import '[\w:]*::self'", "use_self"),
    (r"expected type, got ''", "ref_ref_token"),
    (r"got 'union'", "union_ident"),
]
LATER = re.compile(r"\((\w+)\) comes with the rust edition in")


def impl_params(sig):
    """The type parameters of `impl<..>` (lifetimes left out)."""
    h = re.sub(r"^(pub\s+)?(unsafe\s+)?impl", "", sig).strip()
    if not h.startswith("<"):
        return set()
    inner = h[1:skip_angle(h, 0) - 1]
    return {re.match(r"\s*(\w+)", a).group(1) for a in split_top(inner)
            if re.match(r"\s*[A-Za-z_]", a)}


def generic_impl_gap(sig):
    """Which gap a `generic impl ...` error on this impl header shows."""
    trait, _, self_text = parse_impl_header(sig)
    params = impl_params(sig)
    if self_text.startswith("&"):
        return "impl_for_ref"
    if self_text.strip() in params:
        return "blanket_impl"
    if trait is None:
        return "impl_on_instance"
    m = re.match(r"[\w:]+\s*<(.*)>$", self_text.strip())
    args = [re.sub(r"'\w+", "", a).strip() for a in split_top(m.group(1))] if m else []
    args = [a for a in args if a]
    if any(a not in params for a in args) or len(set(args)) != len(args):
        return "impl_on_instance"
    return "impl_param_in_trait"


def classify(err, item):
    msg = err["text"]
    if err["kind"] == "edition.later":
        m = LATER.search(msg)
        return m.group(1) if m else "later_unknown"
    if re.search(r"a generic impl (block )?(is|for slices)", msg):
        sig = item["sig"] if item.get("kind") == "impl" else item.get("block_sig", "")
        return generic_impl_gap(sig) if sig else "impl_param_in_trait"
    for pat, gap in GAPS:
        if re.search(pat, msg):
            return gap
    return "unclassified"


def read_errors(raw=None):
    """[{file, line, kind, text}] of typecheck.txt (rewritten from raw first)."""
    if raw is not None:
        out = []
        for line in open(raw):
            if not re.match(r"[^ ]+:\d+:\d+: error\[", line):
                continue
            line = re.sub(r" \| try: .*$", "", line.rstrip("\n"))
            line = line.replace("compiler/std2/", "", 1) if line.startswith("compiler/std2/") else line
            out.append(line)
        with open(TYPECHECK, "w") as fh:
            fh.write("# The front's errors on compiler/std2 (tools/std2-checklist.py's header): "
                     f"{len(out)}.\n" + "".join(l + "\n" for l in out))
    if not os.path.exists(TYPECHECK):
        return None
    errs = []
    for line in open(TYPECHECK):
        m = re.match(r"([^ ]+):(\d+):(\d+): error\[([^\]]+)\] (.*)$", line.rstrip("\n"))
        if m:
            errs.append(dict(file=m.group(1), line=int(m.group(2)), kind=m.group(4),
                             text=f"{m.group(1)}: error[{m.group(4)}] {m.group(5)}"))
    return errs


def errors_to_items(errs, items):
    """Each error's items: the one whose lines hold it (an inherent impl's
    header: each of its members; `<std>`'s duplicate method: std2's item of
    that owner and name). Returns {id(item): [(error, gap)]} and the errors
    no item takes."""
    by = {}
    loose = []
    lines_of = {}
    for err in errs:
        targets = []
        if err["file"] == "<std>":
            m = re.search(r"duplicate method '(\w+)' for type '([^']+)'", err["text"])
            if m:
                targets = [it for it in items if it["owner"] == m.group(2) and it["name"] == m.group(1)]
        elif err["file"] in MARKS:
            if err["file"] not in lines_of:
                lines_of[err["file"]] = open(os.path.join(TREE, err["file"])).read().split("\n")
            fl = lines_of[err["file"]]
            ln = err["line"]
            while ln <= len(fl) and fl[ln - 1].strip().startswith("#[") \
                    and not fl[ln - 1].strip().startswith("#[builtin_impls("):
                ln += 1
            last = None
            for at, what in sorted(MARKS[err["file"]], key=lambda m: m[0]):
                if at > ln:
                    break
                last = what
            if isinstance(last, dict):
                targets = [last]
            elif isinstance(last, tuple):
                targets = list(last[1]["members"])
                for it in targets:
                    it["block_sig"] = last[1]["sig"]
        if not targets:
            loose.append(err)
        for it in targets:
            by.setdefault(id(it), []).append((err, classify(err, it)))
    return by, loose


def mvs_items(volec, wanted_traits):
    """{(owner, name)} of MVS's std and {key: (module, kind)}."""
    try:
        r = subprocess.run([volec, "query", "items", "std", "--budget", "10000000"], capture_output=True,
                           text=True, cwd=TOP, timeout=300)
    except OSError as e:
        die(f"{volec}: {e}")
    if r.returncode != 0:
        die(f"{volec} query items std: {r.stderr.strip()[:200]}")
    keys = {}
    owner = None
    module = "std"
    traits = []
    for line in r.stdout.split("\n"):
        if line.startswith("# "):
            module = line[2:].split("\t")[0]
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        kind, text = parts[1], parts[2]
        if kind in ("impl",):
            trait, own, _ = parse_impl_header(text)
            owner = own
            if trait:
                keys[(own, f"impl {trait}")] = (module, "impl")
                owner = ("traitimpl", own)
            continue
        if kind in ("struct", "enum", "trait", "fn", "const", "static", "type"):
            m = re.search(r"\b(?:fn|struct|enum|trait|const|static|type)\s+(?:var\s+)?(\w+)", text)
            if m:
                keys.setdefault((None, m.group(1)), (module, kind))
                if kind == "trait":
                    traits.append((module, m.group(1)))
            owner = None
            continue
        if kind == "method" and isinstance(owner, str):
            m = re.search(r"\bfn\s+(\w+)", text)
            if m:
                keys.setdefault((owner, m.group(1)), (module, "method"))
    # a trait's methods (not items of their own in `query items`)
    for module, t in traits:
        if t not in wanted_traits:
            continue
        r = subprocess.run([volec, "query", "show", f"{module}::{t}"], capture_output=True, text=True, cwd=TOP,
                           timeout=60)
        for line in r.stdout.split("\n"):
            if line.lstrip().startswith("//"):
                continue
            for m in re.finditer(r"\bfn\s+(\w+)", line):
                keys.setdefault((t, m.group(1)), (module, "trait method"))
    return keys


def read_tsv(name):
    rows = []
    p = os.path.join(TREE, name)
    if not os.path.exists(p):
        return rows
    with open(p) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            rows.append(line.rstrip("\n").split("\t"))
    return rows


def key_of(path):
    """`Vec::push` -> ("Vec", "push"); `println` -> (None, "println");
    `[T]::get` -> ("[T]", "get")."""
    if "::" in path:
        o, n = path.rsplit("::", 1)
        return (o.split("::")[-1] if not o.startswith("[") else o, n)
    return (None, path)


def release_of(later, feats):
    """The latest release of later's features; `-` when one is a front gap
    no release has taken yet."""
    rel = "0.27.0"
    for t in later:
        r = feats.get(t)
        if r is None:
            die(f"later feature '{t}' is not in compiler/std2/features.tsv")
        if r == "-":
            return "-"
        if tuple(int(x) for x in r.split(".")) > tuple(int(x) for x in rel.split(".")):
            rel = r
    return rel


def main():
    args = sys.argv[1:]
    volec = os.path.join(TOP, "target", "tools", "volec")
    check = False
    raw = None
    while args:
        a = args.pop(0)
        if a == "--volec":
            volec = args.pop(0)
        elif a == "--errors":
            raw = args.pop(0)
        elif a == "--check":
            check = True
        else:
            die(f"unknown argument {a}")
    feats = {r[0]: r[1] for r in read_tsv("features.tsv")}
    items = read_tree()
    errs = read_errors(raw)
    if errs is None:
        die("compiler/std2/typecheck.txt is missing: --errors FILE (the header says how to make one)")
    by, loose = errors_to_items(errs, items)
    mvs = mvs_items(volec, SCOPE_OWNERS | {it["name"] for it in items if it["kind"] == "trait"})
    used = set()
    rows = []
    for it in items:
        own = it["owner"]
        auto = (OWNER_ALIASES.get(own, own) if own else None, it["name"])
        status = it["status"]
        src = ""
        if it["mvs"]:
            for p in it["mvs"]:
                mk = key_of(p)
                if mk not in mvs:
                    die(f"{it['file']}:{it['line']}: `// mvs: {p}` names no MVS item")
                used.add(mk)
            src = ",".join(it["mvs"])
            status = status or "kept"
        elif auto in mvs:
            used.add(auto)
            src = (f"{auto[0]}::" if auto[0] else "") + auto[1]
            status = status or "kept"
        elif status == "renamed":
            die(f"{it['file']}:{it['line']}: renamed needs `// mvs: PATH`")
        else:
            status = status or "new"
        name = (f"{own}::" if own else "") + it["name"]
        test = "std2_" + re.sub(r"[^A-Za-z0-9]+", "_", it["module"][len("std"):].strip(":") + "_" + name).strip("_")
        got = by.get(id(it), [])
        forced = it.get("forced", [])
        real = sorted({g for _, g in got} | set(forced))
        if not got and not forced:
            state = "ok"
        elif all(e["kind"] == "edition.later" or g in forced for e, g in got):
            state = "later"
        else:
            state = "error"
        predicted = [t for t in it["later"] if t not in real]
        rows.append([it["module"], name, it["kind"], status, src, state, ",".join(real),
                     release_of(real, feats), ",".join(predicted), test.lower(), it["why"], it["sig"]])
    gone = read_tsv("gone.tsv")
    for g in gone:
        if len(g) < 3:
            die(f"gone.tsv: a line needs MODULE, MVS item and replacement: {g}")
        k = key_of(g[1])
        if k[1] == "*":
            # Owner::* : the type and every item of it that no std2 item names
            keys = sorted(x for x in mvs if x[0] == k[0] and x not in used) + \
                ([(None, k[0])] if (None, k[0]) in mvs and (None, k[0]) not in used else [])
            if not keys:
                die(f"gone.tsv: {g[1]} names no MVS item")
        elif k not in mvs:
            die(f"gone.tsv: {g[1]} is no MVS item")
        else:
            keys = [k]
        for k in keys:
            used.add(k)
            rows.append([g[0], "-", "-", "gone", (f"{k[0]}::" if k[0] else "") + k[1], "", "", "", "", "", g[2], ""])
    # rewrite.tsv: every row's MVS item exists, and its four columns
    rewrites = [r for r in read_tsv("rewrite.tsv") if r[0] != "mvs"]
    for r in rewrites:
        if len(r) != 4:
            die(f"rewrite.tsv: a row needs mvs, when, rust and note: {r}")
        if key_of(r[0]) not in mvs:
            die(f"rewrite.tsv: {r[0]} is no MVS item")
    # completeness: in-scope MVS items no line accounts for
    missing = sorted(f"{o + '::' if o else ''}{n} ({m})" for (o, n), (m, k) in mvs.items()
                     if (o in SCOPE_OWNERS or (o is None and m in SCOPE_MODULES and k == "fn"))
                     and (o, n) not in used and not n.startswith("__"))
    head = ["module", "item", "kind", "status", "mvs", "check", "later", "release", "predicted", "test", "note",
            "signature"]
    text = "# Generated by tools/std2-checklist.py from compiler/std2 (do not edit): see its header.\n"
    text += "\t".join(head) + "\n" + "".join("\t".join(r) + "\n" for r in rows)
    if check:
        old = open(OUT).read() if os.path.exists(OUT) else ""
        if old != text:
            print("compiler/std2/checklist.tsv is stale: tools/std2-checklist.py", file=sys.stderr)
            sys.exit(1)
    else:
        with open(OUT, "w") as fh:
            fh.write(text)
    # the counts
    mods = {}
    for r in rows:
        c = mods.setdefault(r[0], {"kept": 0, "renamed": 0, "changed": 0, "new": 0, "gone": 0})
        c[r[3]] += 1
    tot = {k: sum(c[k] for c in mods.values()) for k in ("kept", "renamed", "changed", "new", "gone")}
    print(f"{'module':28} {'kept':>5} {'renam':>5} {'chang':>5} {'new':>5} {'gone':>5}")
    for m in sorted(mods):
        c = mods[m]
        print(f"{m:28} {c['kept']:5} {c['renamed']:5} {c['changed']:5} {c['new']:5} {c['gone']:5}")
    print(f"{'total':28} {tot['kept']:5} {tot['renamed']:5} {tot['changed']:5} {tot['new']:5} {tot['gone']:5}"
          f"   ({len(items)} std2 items)")
    per = {}
    for r in rows:
        for t in filter(None, r[6].split(",")):
            per[t] = per.get(t, 0) + 1
    print(f"rewrite.tsv: {len(rewrites)} rows, for {len({r[0] for r in rewrites})} MVS items")
    st = {k: sum(1 for r in rows if r[5] == k) for k in ("ok", "later", "error")}
    unsched = sum(1 for r in rows if r[5] == "error" and r[7] == "-")
    kinds = {}
    for e in errs:
        kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
    print(f"typecheck.txt: {len(errs)} errors (" + ", ".join(f"{kinds[k]} {k}" for k in sorted(kinds)) + ")")
    print(f"items that typecheck: {st['ok']} of {len(items)}; only edition.later: {st['later']}; "
          f"a plain error: {st['error']} ({unsched} of them a gap no release has taken)")
    for t in sorted(per, key=lambda t: (-per[t], t)):
        print(f"  {t} ({feats[t] if feats[t] != '-' else 'a gap, not scheduled'}): {per[t]}")
    if loose:
        print(f"errors no item takes ({len(loose)}): " + "; ".join(f"{e['file']}:{e['line']}" for e in loose))
    if missing:
        print(f"unaccounted MVS items in scope ({len(missing)}): " + ", ".join(missing), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
