## (0.25.2) C imports. Without the include paths the header is not found,
## and the program's other errors are still published; the client's
## settings (workspace/didChangeConfiguration; initializationOptions at
## the start) give vole.includePaths (as a build's -I, relative to the
## workspace) and vole.cSources: the program is read again. Go to
## definition on the import's string opens the header; on a name used
## through the alias it lands on the header's declaration (a function:
## also its body in a C source), a hover shows the C declaration. A file
## beside main.vl that no `mod` item names gets a note.
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"rootUri":"file://@DIR@"}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-16","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true,"workspaceSymbolProvider":true,"documentFormattingProvider":true,"documentRangeFormattingProvider":true,"completionProvider":{"triggerCharacters":[".",":"],"resolveProvider":true},"signatureHelpProvider":{"triggerCharacters":["(",","]}},"serverInfo":{"name":"volec","version":"@VERSION@"}}}
> {"jsonrpc":"2.0","method":"initialized","params":{}}
> @open main.vl
> {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":6,"character":20}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/main.vl","diagnostics":[{"range":{"start":{"line":3,"character":7},"end":{"line":3,"character":17}},"severity":1,"code":"C import","source":"volec","message":"header not found: widget.h"},{"range":{"start":{"line":9,"character":21},"end":{"line":9,"character":22}},"severity":1,"code":"type error","source":"volec","message":"expected 'bool', got 'i64'\nhelp: a condition is a bool: compare (`x != 0`); bitwise not is `~x`","relatedInformation":[{"location":{"uri":"file://@DIR@/main.vl","range":{"start":{"line":9,"character":21},"end":{"line":9,"character":22}}},"message":"try: 2 != 0"},{"location":{"uri":"file://@DIR@/main.vl","range":{"start":{"line":9,"character":21},"end":{"line":9,"character":22}}},"message":"try: volec fix --suggested @DIR@/main.vl"}]}]}}
< {"jsonrpc":"2.0","id":2,"result":null}
> {"jsonrpc":"2.0","method":"workspace/didChangeConfiguration","params":{"settings":{"vole":{"includePaths":["inc"],"cSources":["inc/widget.c"]}}}}
## the import's string: the header
> {"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":3,"character":8}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/main.vl","diagnostics":[{"range":{"start":{"line":8,"character":22},"end":{"line":8,"character":23}},"severity":1,"code":"type error","source":"volec","message":"expected 'bool', got 'i32'\nhelp: a condition is a bool: compare (`x != 0`); bitwise not is `~x`","relatedInformation":[{"location":{"uri":"file://@DIR@/main.vl","range":{"start":{"line":8,"character":22},"end":{"line":8,"character":23}}},"message":"try: k != 0"},{"location":{"uri":"file://@DIR@/main.vl","range":{"start":{"line":8,"character":22},"end":{"line":8,"character":23}}},"message":"try: volec fix --suggested @DIR@/main.vl"}]},{"range":{"start":{"line":9,"character":21},"end":{"line":9,"character":22}},"severity":1,"code":"type error","source":"volec","message":"expected 'bool', got 'i64'\nhelp: a condition is a bool: compare (`x != 0`); bitwise not is `~x`","relatedInformation":[{"location":{"uri":"file://@DIR@/main.vl","range":{"start":{"line":9,"character":21},"end":{"line":9,"character":22}}},"message":"try: 2 != 0"},{"location":{"uri":"file://@DIR@/main.vl","range":{"start":{"line":9,"character":21},"end":{"line":9,"character":22}}},"message":"try: volec fix --suggested @DIR@/main.vl"}]}]}}
< {"jsonrpc":"2.0","id":3,"result":{"uri":"file://@DIR@/inc/widget.h","range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}}}}
> {"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":3,"character":8}}}
< {"jsonrpc":"2.0","id":4,"result":{"contents":{"kind":"markdown","value":"```c\n#include <widget.h>\n```\n`@DIR@/inc/widget.h` (the header this import reads)\n"},"range":{"start":{"line":3,"character":7},"end":{"line":3,"character":17}}}}
## a function (its body, its declaration), a macro, a struct
> {"jsonrpc":"2.0","id":5,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":7,"character":24}}}
< {"jsonrpc":"2.0","id":5,"result":[{"uri":"file://@DIR@/inc/widget.c","range":{"start":{"line":3,"character":4},"end":{"line":3,"character":16}}},{"uri":"file://@DIR@/inc/widget.h","range":{"start":{"line":12,"character":4},"end":{"line":12,"character":16}}}]}
> {"jsonrpc":"2.0","id":6,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":7,"character":24}}}
< {"jsonrpc":"2.0","id":6,"result":{"contents":{"kind":"markdown","value":"```vole\nfn widget_count(p0: *widget, p1: i32) -> i32\neffects: alloc(Gpa, extern) io global panic diverge (inferred)\nfeatures: none\n```\n```c\nint widget_count(const struct widget *w,\n                 int n);\n```\ndeclared in `widget.h:13` (C)\n\n`crate::w::widget_count` (fn)\n"},"range":{"start":{"line":7,"character":24},"end":{"line":7,"character":36}}}}
> {"jsonrpc":"2.0","id":7,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":6,"character":20}}}
< {"jsonrpc":"2.0","id":7,"result":{"uri":"file://@DIR@/inc/widget.h","range":{"start":{"line":4,"character":8},"end":{"line":4,"character":18}}}}
> {"jsonrpc":"2.0","id":8,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":6,"character":20}}}
< {"jsonrpc":"2.0","id":8,"result":{"contents":{"kind":"markdown","value":"```vole\nconst WIDGET_MAX: i32 = 8\n```\n```c\n#define WIDGET_MAX 8\n```\ndeclared in `widget.h:5` (C)\n\n`crate::w::WIDGET_MAX` (const)\n"},"range":{"start":{"line":6,"character":20},"end":{"line":6,"character":30}}}}
> {"jsonrpc":"2.0","id":9,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":7,"character":46}}}
< {"jsonrpc":"2.0","id":9,"result":{"uri":"file://@DIR@/inc/widget.h","range":{"start":{"line":6,"character":7},"end":{"line":6,"character":13}}}}
> {"jsonrpc":"2.0","id":10,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":7,"character":46}}}
< {"jsonrpc":"2.0","id":10,"result":{"contents":{"kind":"markdown","value":"```vole\nstruct widget\n```\n```c\nstruct widget {\n    int id;\n    int size;\n};\n```\ndeclared in `widget.h:7` (C)\n\n`crate::w::widget` (struct)\n"},"range":{"start":{"line":7,"character":46},"end":{"line":7,"character":52}}}}
## a file of no `mod` item
> @open stray.vl
> {"jsonrpc":"2.0","id":11,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file://@DIR@/stray.vl"}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/stray.vl","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"severity":3,"code":"lsp.not-in-program","source":"volec","message":"not checked: this file is not a module of the program @DIR@/main.vl (no `mod stray;` reaches it)\nhelp: add `mod stray;` to the module above it, or check it alone: volec check @DIR@/stray.vl"}]}}
< {"jsonrpc":"2.0","id":11,"result":[]}
> {"jsonrpc":"2.0","id":12,"method":"shutdown"}
< {"jsonrpc":"2.0","id":12,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
