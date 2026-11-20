#!/bin/sh
# XFAIL: RT-137: LSP completion after `n.` on an integer offers 6 methods; the compiler-provided integer methods (wrapping_add, checked_add, count_ones, ...) are missing, and query def cannot find them (0.30.2)
# RT-137 (R302C-35): completion after `n.` on an i64 offers abs, pow,
# max, min, clamp, clone_from; the integer methods the compiler provides
# are not in it, and `volec query def i64::wrapping_add` finds nothing.
# Passes when completion offers them. Needs python3.
# Usage: rt_137_lsp_complete_int_methods.sh VOLEC (default volec).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
mkdir "$w/root"
cat > "$w/root/main.vl" <<'VL'
fn main() {
    let n = 5i64;
    n.
}
VL
cat > "$w/complete.py" <<'PY'
# R302C-35's client: textDocument/completion at line 2, character 6 (after
# `n.`, from 0) of prog/main.vl must offer wrapping_add, checked_add,
# count_ones and leading_zeros (all callable on n). Prints the labels, exits
# 1 if any is missing.
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
r = req(2, 'textDocument/completion', {'textDocument': {'uri': uri}, 'position': {'line': 2, 'character': 6}})
res = (r or {}).get('result') or []
if isinstance(res, dict): res = res.get('items', [])
labels = sorted(x['label'] for x in res)
req(3, 'shutdown', None); send({'jsonrpc': '2.0', 'method': 'exit'})
want = ['checked_add', 'count_ones', 'leading_zeros', 'wrapping_add']
print('completion after n.:', labels, 'want', want, 'in them')
sys.exit(0 if all(w in labels for w in want) else 1)
PY
perl -e 'alarm 60; exec @ARGV' python3 -I "$w/complete.py" "$V" "$w/root"
