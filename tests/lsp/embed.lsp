## (0.25.3) include_str and include_bytes: go to definition on the path
## string, or on the name, opens the embedded file (relative to the file
## holding the call); nothing is published (the program checks).
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"rootUri":"file://@DIR@"}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-16","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true,"workspaceSymbolProvider":true,"documentFormattingProvider":true,"documentRangeFormattingProvider":true,"completionProvider":{"triggerCharacters":[".",":"],"resolveProvider":true},"signatureHelpProvider":{"triggerCharacters":["(",","]}},"serverInfo":{"name":"volec","version":"@VERSION@"}}}
> {"jsonrpc":"2.0","method":"initialized","params":{}}
> @open main.vl
> {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":0,"character":32}}}
< {"jsonrpc":"2.0","id":2,"result":{"uri":"file://@DIR@/shaders/blur.wgsl","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}}}}
> {"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":3,"character":14}}}
< {"jsonrpc":"2.0","id":3,"result":{"uri":"file://@DIR@/shaders/blur.wgsl","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}}}}
> {"jsonrpc":"2.0","id":4,"method":"shutdown"}
< {"jsonrpc":"2.0","id":4,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
