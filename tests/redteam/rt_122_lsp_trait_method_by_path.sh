#!/bin/sh
# XFAIL: RT-122: the LSP has no definition for a trait method called by path (A::m(&s), <S as B>::m(&s)) and leaves those calls out of its references (0.30.2)
# RT-122: `volec query refs A::m` lists both path calls; the LSP answers
# null for their definitions and leaves them out of the methods'
# references. In a generic body it also sends `t.m()` (T: A) to the
# type's inherent m (the RT-72 family, in the editor). Passes when the
# definitions and references are right. Needs python3.
# Usage: rt_122_lsp_trait_method_by_path.sh VOLEC (default volec).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
mkdir "$w/root"
cat > "$w/root/main.vl" <<'VL'
trait A {
    fn m(&self) -> i64;
}

trait B {
    fn m(&self) -> i64;
}

struct S;

impl S {
    fn m(&self) -> i64 {
        0
    }
}

impl A for S {
    fn m(&self) -> i64 {
        1
    }
}

impl B for S {
    fn m(&self) -> i64 {
        2
    }
}

fn ga<T: A>(t: &T) -> i64 {
    t.m()
}

fn main() {
    let s = S;
    println("{} {} {} {}", s.m(), A::m(&s), <S as B>::m(&s), ga(&s));
}
VL
cat > "$w/ufcs.py" <<'PY'
# R302C-26's client. prog/main.vl (lines and characters from 0): A::m is
# declared at (1, 7), B::m at (5, 7), <S as A>::m at (17, 7), <S as B>::m at
# (23, 7); line 34 calls `A::m(&s)` (m at character 37) and `<S as B>::m(&s)`
# (m at character 55). Wanted: definition at (34, 37) is <S as A>::m or A::m,
# at (34, 55) <S as B>::m or B::m; references of <S as A>::m (17, 7) include
# (34, 37), of <S as B>::m (23, 7) include (34, 55). Got (0.30.2): null, null,
# and neither call in the references. Prints the answers, exits 1 if wrong.
import json, subprocess, sys, os
V, root = sys.argv[1], os.path.abspath(sys.argv[2])
p = subprocess.Popen([V, 'lsp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=root)
def send(o):
    b = json.dumps(o).encode(); p.stdin.write(b'Content-Length: %d\r\n\r\n' % len(b) + b); p.stdin.flush()
def recv():
    h = b''
    while not h.endswith(b'\r\n\r\n'):
        c = p.stdout.read(1)
        if not c: return None
        h += c
    n = int([l for l in h.split(b'\r\n') if l.lower().startswith(b'content-length')][0].split(b':')[1])
    return json.loads(p.stdout.read(n))
def req(i, m, params):
    send({'jsonrpc': '2.0', 'id': i, 'method': m, 'params': params})
    while True:
        r = recv()
        if r is None or r.get('id') == i: return r
req(1, 'initialize', {'rootUri': 'file://' + root, 'capabilities': {}})
send({'jsonrpc': '2.0', 'method': 'initialized', 'params': {}})
uri = 'file://' + root + '/main.vl'
send({'jsonrpc': '2.0', 'method': 'textDocument/didOpen', 'params': {'textDocument': {'uri': uri, 'languageId': 'vole', 'version': 1, 'text': open(root + '/main.vl').read()}}})
def pos(l, c): return {'textDocument': {'uri': uri}, 'position': {'line': l, 'character': c}, 'context': {'includeDeclaration': True}}
def at(x): return (x['range']['start']['line'], x['range']['start']['character'])
ok = True
for i, (l, c, want) in enumerate([(34, 37, [(17, 7), (1, 7)]), (34, 55, [(23, 7), (5, 7)])]):
    r = (req(10 + i, 'textDocument/definition', pos(l, c)) or {}).get('result')
    if isinstance(r, list): r = r[0] if r else None
    got = at(r) if r else None
    print('definition at', (l, c), got, 'want one of', want)
    ok = ok and got in want
for i, (l, c, call) in enumerate([(17, 7, (34, 37)), (23, 7, (34, 55))]):
    r = (req(20 + i, 'textDocument/references', pos(l, c)) or {}).get('result') or []
    got = sorted(at(x) for x in r)
    print('references of', (l, c), got, 'want', call, 'in them')
    ok = ok and call in got
req(3, 'shutdown', None); send({'jsonrpc': '2.0', 'method': 'exit'})
sys.exit(0 if ok else 1)
PY
perl -e 'alarm 60; exec @ARGV' python3 -I "$w/ufcs.py" "$V" "$w/root"
