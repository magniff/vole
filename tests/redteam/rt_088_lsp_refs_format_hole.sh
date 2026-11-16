#!/bin/sh
# XFAIL: RT-88: the LSP's references of a local leave out its uses in format holes (query refs lists them) (0.30.2)
# RT-88: textDocument/references of the local `total` lists its `let` and
# its use as an argument, not its use in the format hole `{total}`; an
# editor's rename by these answers leaves the hole naming the old local.
# `volec query refs main.vl:4:9` lists all three, and a const's hole use
# is listed. Passes when the LSP lists all three. Needs python3.
# Usage: rt_088_lsp_refs_format_hole.sh VOLEC (default volec).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
cat > "$w/main.vl" <<'VL'
const K: i64 = 3;

fn main() {
    let total = K + 1;
    println("{total} {K}");
    println("{}", total);
}
VL
cat > "$w/refs.py" <<'PY'
# R302C-10's client: textDocument/references of the local `total` (line 3,
# character 8, from 0) must list its uses in the format hole `{total}` (line
# 4, character 14) and in `println("{}", total)` (line 5, character 18),
# as `volec query refs main.vl:4:9` does; prints the answer, exits 1 if not.
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
r = req(2, 'textDocument/references', {'textDocument': {'uri': uri}, 'position': {'line': 3, 'character': 8}, 'context': {'includeDeclaration': True}})
got = sorted((x['range']['start']['line'], x['range']['start']['character']) for x in (r or {}).get('result') or [])
req(3, 'shutdown', None); send({'jsonrpc': '2.0', 'method': 'exit'})
want = [(3, 8), (4, 14), (5, 18)]
print('references of total:', got, 'want', want)
sys.exit(0 if got == want else 1)
PY
mkdir "$w/root" && mv "$w/main.vl" "$w/root/main.vl"
perl -e 'alarm 60; exec @ARGV' python3 -I "$w/refs.py" "$V" "$w/root"
