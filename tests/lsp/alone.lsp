## (0.25.2) A file with no main.vl in its directory or above (up to a
## repository's top or the home directory) is a program of its own, as
## `volec check FILE` reads it: a library of one file (as
## examples/python-ext/vole_hello.vl) has its errors published, an unsafe
## operation outside `unsafe` among them. A document that is no file on
## disk gets a note saying so, never silence.
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-16","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true,"workspaceSymbolProvider":true,"documentFormattingProvider":true,"documentRangeFormattingProvider":true,"completionProvider":{"triggerCharacters":[".",":"],"resolveProvider":true},"signatureHelpProvider":{"triggerCharacters":["(",","]}},"serverInfo":{"name":"volec","version":"@VERSION@"}}}
> {"jsonrpc":"2.0","method":"initialized","params":{}}
> @open lib.vl
> {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/lib.vl"},"position":{"line":3,"character":4}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/lib.vl","diagnostics":[{"range":{"start":{"line":3,"character":4},"end":{"line":3,"character":5}},"severity":1,"code":"unsafe","source":"volec","message":"indexing a raw pointer is unsafe\nhelp: `p[0]` is pointer arithmetic; the value p points to is `*p` (`*p = x` writes it), unsafe as well through a raw pointer (not a borrow: a `*T` parameter, a local, a field), so put it in an `unsafe { ... }` block (the try: line wraps every such place)","relatedInformation":[{"location":{"uri":"file://@DIR@/lib.vl","range":{"start":{"line":3,"character":4},"end":{"line":3,"character":5}}},"message":"try: volec fix --only unsafe @DIR@/lib.vl"}]},{"range":{"start":{"line":7,"character":19},"end":{"line":7,"character":20}},"severity":1,"code":"type error","source":"volec","message":"expected 'bool', got 'i64'\nhelp: a condition is a bool: compare (`x != 0`); bitwise not is `~x`","relatedInformation":[{"location":{"uri":"file://@DIR@/lib.vl","range":{"start":{"line":7,"character":19},"end":{"line":7,"character":20}}},"message":"try: x != 0"},{"location":{"uri":"file://@DIR@/lib.vl","range":{"start":{"line":7,"character":19},"end":{"line":7,"character":20}}},"message":"try: volec fix --suggested @DIR@/lib.vl"}]}]}}
< {"jsonrpc":"2.0","id":2,"result":{"contents":{"kind":"markdown","value":"```vole\np: *u8\n```\n"},"range":{"start":{"line":3,"character":4},"end":{"line":3,"character":5}}}}
> {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"untitled:Untitled-1","languageId":"vole","version":1,"text":"fn main() {}\n"}}}
> {"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"untitled:Untitled-1"},"position":{"line":0,"character":3}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"untitled:Untitled-1","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"severity":3,"code":"lsp.not-a-file","source":"volec","message":"not checked: volec checks files on disk\nhelp: save this document as a .vl file (a program of its own, or a module of one: `mod NAME;` in its main.vl)"}]}}
< {"jsonrpc":"2.0","id":3,"result":null}
> {"jsonrpc":"2.0","id":4,"method":"shutdown"}
< {"jsonrpc":"2.0","id":4,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
