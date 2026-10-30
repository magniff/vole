## 0.26.2: hover on a name in a format literal's hole shows its type, as
## on an f-string's hole, on a width's `name$` too, with the name's range;
## on the literal's text (`items`), whatever the literal answers.
## quiet
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"rootUri":"file://@DIR@"}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-16","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true,"workspaceSymbolProvider":true,"documentFormattingProvider":true,"documentRangeFormattingProvider":true,"completionProvider":{"triggerCharacters":[".",":"],"resolveProvider":true},"signatureHelpProvider":{"triggerCharacters":["(",","]}},"serverInfo":{"name":"volec","version":"@VERSION@"}}}
> {"jsonrpc":"2.0","method":"initialized","params":{}}
> @open main.vl
> {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":5,"character":15}}}
< {"jsonrpc":"2.0","id":2,"result":{"contents":{"kind":"markdown","value":"```vole\ni64\n```\n"},"range":{"start":{"line":5,"character":14},"end":{"line":5,"character":19}}}}
> {"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":5,"character":37}}}
< {"jsonrpc":"2.0","id":3,"result":{"contents":{"kind":"markdown","value":"```vole\ni64\n```\n"},"range":{"start":{"line":5,"character":36},"end":{"line":5,"character":41}}}}
> {"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":5,"character":50}}}
< {"jsonrpc":"2.0","id":4,"result":{"contents":{"kind":"markdown","value":"```vole\ni64\n```\n"},"range":{"start":{"line":5,"character":48},"end":{"line":5,"character":53}}}}
> {"jsonrpc":"2.0","id":6,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":5,"character":22}}}
< {"jsonrpc":"2.0","id":6,"result":{"contents":{"kind":"markdown","value":"```vole\n()\n```\n"},"range":{"start":{"line":5,"character":12},"end":{"line":5,"character":55}}}}
> {"jsonrpc":"2.0","id":5,"method":"shutdown"}
< {"jsonrpc":"2.0","id":5,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
