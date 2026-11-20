## XFAIL: RT-92: query type (and the LSP's hover) gives a `&str` local the type `&[u8]` (0.30.2)
## `let s = "x";`, `let a: &str = "x";` and `let g = give();` (a fn
## returning `&'static str`) are &str; `query type` answers `&[u8]` for
## each, and for `s` in `s.len()`, and a tuple holding one is `(&[u8], i32)`;
## the LSP's hover on the same locals says `s: &[u8]`. `Option<&str>` is
## shown right. A reader (or an agent) told `&[u8]` writes code that does
## not check (`s.chars()` has no such method on a slice).
$ query type main.vl:6:9
&str	s
$ query type main.vl:7:9
&str	a
$ query type main.vl:8:9
&str	g
