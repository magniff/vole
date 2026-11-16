## XFAIL: RT-TL-23: a byte that is not UTF-8 after a quote panics the lexer, and between quotes is read as Latin-1 (open)
## The files are written here (no non-UTF-8 file in the tree). Not the
## known "str literal ... an error quoting it": no str, no error quoted.
## a.vl: `let c = '` then byte 0xE2 and `;`: the lexer itself dies,
## front/lexer/strings.vl:399:18 unwrap on Utf8Error (exit 101); the same
## for a lifetime, `fn f<'` 0xE2 `>()`, and under fmt. b.vl: `'` 0xE2 `'`
## checks and is the char U+00E2: a source that is not UTF-8 must be
## refused. (c.vl, `let e = 'é;`, gets "character literal 'é' is not ASCII
## (a character is one byte, u8)", wrong: 'é' is a char.)
% printf "fn main() -> i32 {\n    let c = '\342;\n    0\n}\n" > a.vl && volec check a.vl 2>&1 | sed 's/:[0-9]*:[0-9]*: error\[[a-z. ]*\].*/: refused/'; echo "exit $?"
a.vl: refused
exit 0
% printf "fn f<'\342>() {}\nfn main() -> i32 {\n    0\n}\n" > l.vl && volec check l.vl 2>&1 | sed 's/:[0-9]*:[0-9]*: error\[[a-z. ]*\].*/: refused/'
l.vl: refused
% printf "fn main() -> i32 {\n    let c = '\342';\n    0\n}\n" > b.vl && volec check b.vl 2>&1 | sed 's/:[0-9]*:[0-9]*: error\[[a-z. ]*\].*/: refused/'
b.vl: refused
