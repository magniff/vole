#!/bin/sh
# XFAIL: RT-243: the LSP's signature help is null on a path call through a primitive (`i64::pow(2, 3)`), a turbofish (`G::<i64>::put(&mut g, 7, 8)`) and a qualified path (`<S as Tr>::m(&s, 3, 4)`); `Option::unwrap_or(o, 4)` and `G::put(&mut g, 5, 6)` are right (0.30.2)
# signatureHelp at each argument must name the parameter under the cursor.
# Needs python3; the client and the program are inline below.
set -u
VOLEC=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/main.vl" <<'VL'
trait Tr {
    fn m(&self, a: i64, b: u8) -> i64;
}

struct S {
    k: i64,
}

impl Tr for S {
    fn m(&self, a: i64, b: u8) -> i64 {
        self.k + a + b as i64
    }
}

struct G<T> {
    v: T,
}

impl<T: Copy> G<T> {
    fn put(&mut self, x: T, n: i64) -> i64 {
        self.v = x;
        n
    }
}

fn main() {
    let s = S { k: 1 };
    let o: Option<i64> = None;
    let mut g = G { v: 1i64 };
    let a = i64::pow(2, 3);
    let c = Option::unwrap_or(o, 4);
    let d = G::put(&mut g, 5, 6);
    let e = G::<i64>::put(&mut g, 7, 8);
    let f = <S as Tr>::m(&s, 3, 4);
    println("{} {} {} {} {}", a, c, d, e, f);
}
VL
cat > "$T/sig.py" <<'PY'
# R302E-20's client: textDocument/signatureHelp (lines from 0) at each argument of
# `i64::pow(2, 3)` (29), `Option::unwrap_or(o, 4)` (30), `G::put(&mut g, 5, 6)` (31),
# `G::<i64>::put(&mut g, 7, 8)` (32) and `<S as Tr>::m(&s, 3, 4)` (33) must name the
# parameter under the cursor. Prints what it got, exits 1 when one differs.
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
bad = 0
PTS = [(29, 21, 'self'), (29, 24, 'exp: u32'), (30, 30, 'self'), (30, 33, 'default: T'), (31, 19, '&mut self'), (31, 27, 'x: T'), (31, 30, 'n: i64'), (32, 26, '&mut self'), (32, 34, 'x: T'), (32, 37, 'n: i64'), (33, 25, '&self'), (33, 29, 'a: i64'), (33, 32, 'b: u8')]
for i, (ln, c, want) in enumerate(PTS):
    r = req(10 + i, 'textDocument/signatureHelp', {'textDocument': {'uri': uri}, 'position': {'line': ln, 'character': c}})
    res = (r or {}).get('result')
    got = None
    if res and res.get('signatures'):
        sig = res['signatures'][res.get('activeSignature', 0)]
        a = res.get('activeParameter', sig.get('activeParameter', 0))
        if a is not None and 0 <= a < len(sig['parameters']):
            lab = sig['parameters'][a]['label']
            got = sig['label'][lab[0]:lab[1]] if isinstance(lab, list) else lab
    print('line %d char %d: label %r active %r, want %r' % (ln, c, (res or {}).get('signatures', [{}])[0].get('label') if res and res.get('signatures') else None, got, want))
    if got != want: bad = 1
req(99, 'shutdown', None); send({'jsonrpc': '2.0', 'method': 'exit'})
sys.exit(bad)
PY
out=$(perl -e 'alarm 60; exec @ARGV' python3 -I "$T/sig.py" "$VOLEC" "$T" 2>&1)
rc=$?
[ $rc -eq 0 ] || { echo "FAIL: signature help (exit $rc):"; echo "$out" | head -13; exit 1; }
echo ok
