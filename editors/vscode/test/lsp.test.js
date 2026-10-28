// The language server as the extension uses it (npm run test:lsp):
// `volec lsp` over stdio, asked what VS Code asks on save (formatting)
// and while typing (completion, resolve), with VS Code's capabilities.
// The compiler: $VOLEC, else the repository's target/volec, else volec on
// PATH; none: skipped. Plain node, no dependencies.

"use strict";
const assert = require("assert");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

function findCompiler() {
  const cands = [process.env.VOLEC, path.join(__dirname, "..", "..", "..", "target", "volec")];
  for (const c of cands) {
    if (c && fs.existsSync(c)) return c;
  }
  const r = cp.spawnSync("sh", ["-c", "command -v volec"], { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : undefined;
}

class Client {
  constructor(compiler, cwd) {
    this.proc = cp.spawn(compiler, ["lsp"], { cwd, stdio: ["pipe", "pipe", "inherit"] });
    this.buf = Buffer.alloc(0);
    this.waiting = new Map();
    this.next = 1;
    this.proc.stdout.on("data", (d) => this.read(d));
  }
  read(d) {
    this.buf = Buffer.concat([this.buf, d]);
    for (;;) {
      const h = this.buf.indexOf("\r\n\r\n");
      if (h < 0) return;
      const m = /Content-Length: (\d+)/i.exec(this.buf.subarray(0, h).toString());
      const n = Number(m[1]);
      if (this.buf.length < h + 4 + n) return;
      const msg = JSON.parse(this.buf.subarray(h + 4, h + 4 + n).toString());
      this.buf = this.buf.subarray(h + 4 + n);
      if (msg.id !== undefined && this.waiting.has(msg.id)) {
        this.waiting.get(msg.id)(msg);
        this.waiting.delete(msg.id);
      }
    }
  }
  send(msg) {
    const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...msg }));
    this.proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
    this.proc.stdin.write(body);
  }
  request(method, params) {
    const id = this.next++;
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`${method}: no answer`)), 30000);
      this.waiting.set(id, (m) => {
        clearTimeout(t);
        resolve(m);
      });
      this.send({ id, method, params });
    });
  }
  notify(method, params) {
    this.send({ method, params });
  }
}

// The text with LSP's edits applied (positions in UTF-16, as VS Code's).
function applyEdits(text, edits) {
  const lines = [0];
  for (let i = 0; i < text.length; i++) if (text[i] === "\n") lines.push(i + 1);
  const at = (p) => (p.line < lines.length ? lines[p.line] + p.character : text.length);
  const sorted = [...edits].sort((a, b) => at(b.range.start) - at(a.range.start));
  let out = text;
  for (const e of sorted) out = out.slice(0, at(e.range.start)) + e.newText + out.slice(at(e.range.end));
  return out;
}

async function main() {
  const compiler = findCompiler();
  if (!compiler) {
    console.log("skip: no volec (set VOLEC)");
    return;
  }
  const dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "vole-ext-")));
  const file = path.join(dir, "main.vl");
  const uri = `file://${file}`;
  const messy = "fn main(gpa: Gpa) -> i32 {\n  var v: Vec<i64> = Vec::new_in(gpa);\n    v.push( 1 );\n    0\n}\n";
  fs.writeFileSync(file, messy);
  const c = new Client(compiler, dir);
  try {
    const init = await c.request("initialize", {
      processId: process.pid,
      rootUri: `file://${dir}`,
      capabilities: {
        general: { positionEncodings: ["utf-16"] },
        textDocument: {
          completion: { completionItem: { snippetSupport: true, resolveSupport: { properties: ["documentation"] } } },
          formatting: {},
          rangeFormatting: {},
        },
      },
    });
    const caps = init.result.capabilities;
    assert.strictEqual(caps.documentFormattingProvider, true, "formatting");
    assert.strictEqual(caps.documentRangeFormattingProvider, true, "range formatting");
    assert.ok(caps.completionProvider.triggerCharacters.includes("."), "completion after .");
    assert.strictEqual(caps.completionProvider.resolveProvider, true, "resolve");
    c.notify("initialized", {});
    c.notify("textDocument/didOpen", { textDocument: { uri, languageId: "vole", version: 1, text: messy } });

    // format on save: the buffer formatted, then a fixed point
    const opts = { tabSize: 4, insertSpaces: true };
    const f1 = await c.request("textDocument/formatting", { textDocument: { uri }, options: opts });
    assert.ok(f1.result.length > 0, "edits for a text not formatted");
    const formatted = applyEdits(messy, f1.result);
    assert.ok(formatted.includes("    var v: Vec<i64> = Vec::new_in(gpa);\n    v.push(1);"), formatted);
    c.notify("textDocument/didChange", { textDocument: { uri, version: 2 }, contentChanges: [{ text: formatted }] });
    const f2 = await c.request("textDocument/formatting", { textDocument: { uri }, options: opts });
    assert.deepStrictEqual(f2.result, [], "formatted text: no edits");

    // a text that does not parse: no edits
    const broken = formatted.replace("v.push(1);", "v.push(1;");
    c.notify("textDocument/didChange", { textDocument: { uri, version: 3 }, contentChanges: [{ text: broken }] });
    const f3 = await c.request("textDocument/formatting", { textDocument: { uri }, options: opts });
    assert.deepStrictEqual(f3.result, [], "broken text: no edits");

    // completion while typing `v.`, the text not parsing
    const typing = formatted.replace("    v.push(1);\n", "    v.push(1);\n    v.\n");
    c.notify("textDocument/didChange", { textDocument: { uri, version: 4 }, contentChanges: [{ text: typing }] });
    const comp = await c.request("textDocument/completion", {
      textDocument: { uri },
      position: { line: 3, character: 6 },
      context: { triggerKind: 2, triggerCharacter: "." },
    });
    const items = comp.result.items;
    const push = items.find((i) => i.label === "push");
    assert.ok(push, `push in ${items.map((i) => i.label).join(" ")}`);
    assert.strictEqual(push.insertTextFormat, 2, "a snippet");
    assert.match(push.insertText, /^push\(\$\{1:x\}\)/);
    const res = await c.request("completionItem/resolve", push);
    assert.match(res.result.documentation.value, /effects/, "resolve: the hover, effects too");

    // a name: the local, keywords
    const naming = formatted.replace("    v.push(1);\n", "    v.push(1);\n    le\n");
    c.notify("textDocument/didChange", { textDocument: { uri, version: 5 }, contentChanges: [{ text: naming }] });
    const comp2 = await c.request("textDocument/completion", { textDocument: { uri }, position: { line: 3, character: 6 } });
    assert.ok(comp2.result.items.some((i) => i.label === "let"), "keyword let");

    await c.request("shutdown", null);
    c.notify("exit", null);
    await includePaths(compiler, dir);
    console.log(`ok: volec lsp (${compiler}): formatting, completion, resolve, include paths`);
  } finally {
    c.proc.kill();
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

// (0.25.2) vole.includePaths as the extension gives them
// (initializationOptions, relative to the workspace folder): a header
// found only there; go to definition on the import's string opens it,
// on a function through the alias lands on its declaration.
async function includePaths(compiler, top) {
  const dir = path.join(top, "inc-project");
  fs.mkdirSync(path.join(dir, "inc"), { recursive: true });
  fs.writeFileSync(path.join(dir, "inc", "gadget.h"), "/* a header */\nint gadget_size(int n);\n");
  const text = 'import "gadget.h" as g;\n\nfn main() {\n    let n = unsafe { g::gadget_size(2) };\n    println(f"{n}");\n}\n';
  const file = path.join(dir, "main.vl");
  fs.writeFileSync(file, text);
  const uri = `file://${file}`;
  const c = new Client(compiler, dir);
  try {
    await c.request("initialize", {
      processId: process.pid,
      rootUri: `file://${dir}`,
      capabilities: {},
      initializationOptions: { includePaths: ["inc"], cSources: [] },
    });
    c.notify("initialized", {});
    c.notify("textDocument/didOpen", { textDocument: { uri, languageId: "vole", version: 1, text } });
    const h = await c.request("textDocument/definition", { textDocument: { uri }, position: { line: 0, character: 9 } });
    assert.strictEqual(h.result && h.result.uri, `file://${path.join(dir, "inc", "gadget.h")}`, JSON.stringify(h));
    const d = await c.request("textDocument/definition", { textDocument: { uri }, position: { line: 3, character: 24 } });
    assert.strictEqual(d.result && d.result.range.start.line, 1, JSON.stringify(d));
    await c.request("shutdown", null);
    c.notify("exit", null);
  } finally {
    c.proc.kill();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
