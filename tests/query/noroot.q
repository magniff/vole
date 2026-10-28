## No root given, no VOLE_ROOT, and no main.vl here.
$ def nothing_defines_this
error query.no-root: no root (VOLE_ROOT, ./main.vl, ./compiler/src/main.vl)
try: volec query def nothing_defines_this path/to/main.vl
[exit 2]
## (0.25.2) A NAME the programs under the directory define: their roots
## (at most 3).
$ def main
error query.no-root: no root (VOLE_ROOT, ./main.vl, ./compiler/src/main.vl)
try: volec query def main --root xroots0252/examples/demo/main.vl
try: volec query def main --root broken/main.vl
try: volec query def main --root budget/main.vl
[exit 2]
$ refs
error query.usage: refs needs a NAME (a path or its end: f, m::f, T::f, T.field; or FILE:LINE)
try: volec query items
[exit 2]
$ frobnicate x
error query.usage: unknown command 'frobnicate'
try: volec query def x
[exit 2]
