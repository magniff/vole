#!/bin/sh
# XFAIL: RT-463: the LSP's hover on a fn's type parameter whose last bound has type arguments, `Q` in `fn k<Q: A<u8>>(q: &Q)`, returns the rest of the source as one line, the file then std's modules (1.9 KB for this program, 1.8 MB for the review's: "Q: A<u8> (q: & Q) -> i64 { q . a () } fn main () ... pub mod prelude ; ..."), where `fn k<Q: A<u8> + Copy>` gives "Q: A<u8> + Copy" and "a type parameter of `k`" (0.30.2)
# From the second re-review of g302qual (its lspd). Since v0.30.1 at
# least (the same answer). The `>>` that closes the bound and the
# parameter list is the trigger (measured: `A<Option<u8>>` the same,
# `A<u8> + Copy` right). It passes when the hover is under 200 bytes and
# names `Q: A<u8>`. Needs python3.
set -u
VOLEC=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/main.vl" <<'VL'
trait A<T> {
    fn a(&self) -> i64;
}

fn k<Q: A<u8>>(q: &Q) -> i64 {
    q.a()
}

fn main() {
    println("x");
}
VL
cat > "$T/hov.py" <<'PY'
# textDocument/hover at Q of `fn k<Q: A<u8>>` (line 4, character 5, from 0).
import json, subprocess, sys, os
V, root = sys.argv[1], os.path.abspath(sys.argv[2])
p = subprocess.Popen([V, 'lsp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=root, env=dict(os.environ, XDG_CACHE_HOME=root + '/.cache'))
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
r = req(2, 'textDocument/hover', {'textDocument': {'uri': uri}, 'position': {'line': 4, 'character': 5}})
res = (r or {}).get('result')
v = res['contents']['value'] if res else ''
req(3, 'shutdown', None); send({'jsonrpc': '2.0', 'method': 'exit'})
ok = len(v) < 200 and 'Q: A<u8>' in v
print('hover: %d bytes: %r' % (len(v), v[:120]))
sys.exit(0 if ok else 1)
PY
perl -e 'alarm 60; exec @ARGV' python3 "$T/hov.py" "$VOLEC" "$T"
