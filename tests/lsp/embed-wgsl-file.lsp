## (0.26.2) an `embed wgsl K from "x.wgsl";` file is a file of the
## program: its WGSL error is published to the .wgsl file's own URI, at
## its line and column there.
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"rootUri":"file://@DIR@"}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-16","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true,"workspaceSymbolProvider":true,"documentFormattingProvider":true,"documentRangeFormattingProvider":true,"completionProvider":{"triggerCharacters":[".",":"],"resolveProvider":true},"signatureHelpProvider":{"triggerCharacters":["(",","]}},"serverInfo":{"name":"volec","version":"@VERSION@"}}}
> {"jsonrpc":"2.0","method":"initialized","params":{}}
> @open main.vl
> {"jsonrpc":"2.0","id":3,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file://@DIR@/main.vl"}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/shaders/bad.wgsl","diagnostics":[{"range":{"start":{"line":2,"character":11},"end":{"line":2,"character":12}},"severity":1,"code":"wgsl.name","source":"volec","message":"unknown name 'colour'"}]}}
< {"jsonrpc":"2.0","id":3,"result":[{"name":"BAD","detail":"embed wgsl BAD from \"shaders/bad.wgsl\"","kind":13,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":39}},"selectionRange":{"start":{"line":0,"character":11},"end":{"line":0,"character":14}},"children":[{"name":"src","detail":"pub \"sh","kind":8,"range":{"start":{"line":0,"character":20},"end":{"line":0,"character":23}},"selectionRange":{"start":{"line":0,"character":20},"end":{"line":0,"character":38}}}]},{"name":"main","detail":"fn main() -> i32","kind":12,"range":{"start":{"line":2,"character":0},"end":{"line":5,"character":1}},"selectionRange":{"start":{"line":2,"character":3},"end":{"line":2,"character":7}}}]}
> {"jsonrpc":"2.0","id":2,"method":"shutdown"}
< {"jsonrpc":"2.0","id":2,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
