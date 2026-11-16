## XFAIL: RT-TL-14: fmt and the edits leave a CRLF source with mixed line ends (open)
## main.vl is written here with CRLF line ends (a Windows checkout).
## The lexer reads it right (a text block's value is the same as LF's).
## A tool that writes it must keep one kind of line end: all CRLF, or
## all LF. Today `fmt` makes every line LF but a line comment's, whose
## `\r` it keeps (the comment's text), and `refactor rename` and `edit
## patch` write the lines they touch with LF and leave the rest CRLF.
## (`ends`: how many lines end in CR, of how many.)
% printf 'fn add(a: i64, b: i64) -> i64 {\r\n\ta + b // sum\r\n}\r\n\r\nfn main() -> i32 {\r\n\tprintln("{}", add(1, 2));\r\n\t0\r\n}\r\n' > main.vl && git add main.vl && git commit -qm crlf
% volec fmt main.vl >/dev/null 2>&1; awk '/\r$/{c++} END{print (c==0||c==NR)?"ends: consistent":"ends: mixed, " c " of " NR}' main.vl
ends: consistent
% git checkout -q main.vl && volec refactor rename add plus >/dev/null 2>&1; awk '/\r$/{c++} END{print (c==0||c==NR)?"ends: consistent":"ends: mixed, " c " of " NR}' main.vl
ends: consistent
% git checkout -q main.vl && volec edit patch add --old 'a + b' --new 'a + b + 0' >/dev/null 2>&1; awk '/\r$/{c++} END{print (c==0||c==NR)?"ends: consistent":"ends: mixed, " c " of " NR}' main.vl
ends: consistent
