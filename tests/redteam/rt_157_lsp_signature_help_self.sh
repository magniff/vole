#!/bin/sh
# XFAIL: RT-157: the LSP's signature help makes `&self` the active parameter for a method call's first argument, and gives none inside a string argument holding `,` or `(` (0.30.2)
# RT-157 (R302D-5). Passes when each answer is right. Needs python3.
# Usage: rt_157_lsp_signature_help_self.sh VOLEC (default volec).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
mkdir "$w/root"
cat > "$w/root/main.vl" <<'VL'
struct S {
    k: i64,
}

impl S {
    fn m(&self, x: u8, y: &str) -> i64 {
        self.k + x as i64 + y.len() as i64
    }
}

fn main() {
    let s = S { k: 1 };
    let w = s.m(4, "a,(b");
    println("{w}");
}
VL
cat > "$w/sig.py" <<'PY'
# R302D-5's client: textDocument/signatureHelp inside `s.m(4, "a,(b")` (line
# 12 from 0) must make the parameter under the cursor the active one: at the
# `4` (character 16) `x: u8`, at the string's `"`, `,` and `b` (characters
# 19, 21, 23) `y: &str`. Prints what it got, exits 1 when one differs.
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
for i, (c, want) in enumerate([(16, 'x: u8'), (19, 'y: &str'), (21, 'y: &str'), (23, 'y: &str')]):
    r = req(10 + i, 'textDocument/signatureHelp', {'textDocument': {'uri': uri}, 'position': {'line': 12, 'character': c}})
    res = (r or {}).get('result')
    got = None
    if res and res.get('signatures'):
        sig = res['signatures'][res.get('activeSignature', 0)]
        a = res.get('activeParameter', sig.get('activeParameter', 0))
        if a is not None and 0 <= a < len(sig['parameters']):
            lab = sig['parameters'][a]['label']
            got = sig['label'][lab[0]:lab[1]] if isinstance(lab, list) else lab
    print('character %d: active %r, want %r' % (c, got, want))
    if got != want: bad = 1
req(99, 'shutdown', None); send({'jsonrpc': '2.0', 'method': 'exit'})
sys.exit(bad)
PY
perl -e 'alarm 60; exec @ARGV' python3 -I "$w/sig.py" "$V" "$w/root"
