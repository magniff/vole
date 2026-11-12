## (0.28.0, gap 101) `query effects F --why io` of a function whose
## `#[pure]` the program breaks: its set is its declaration's, and the
## chain is the body's, down to the println (the error's `try:` asks it).
$ effects score --why io whybroken028/main.vl
crate::score	panic
  (not: io, by its declaration, which its body breaks:)
  'scaled(x)' at whybroken028/main.vl:12:5 calls 'scaled'
  'clamp(x * 2)' at whybroken028/main.vl:7:5 calls 'clamp'
  'println("clamp {x}")' at whybroken028/main.vl:2:5 calls 'std::fmt::println'
  'write_erased::<W>' at <std>:17364:20 calls 'std::fmt::write_erased'
  'w.write_str(s)' at <std>:17956:5 calls 'IoOut::write_str'
  'self.inner.write_all(s.as_bytes())' at <std>:63153:19 calls 'Stdout::write_all'
  'fd_write_all(self.fd, buf)' at <std>:24676:9 calls 'std::io::fd_write_all'
  'sys_write(fd, buf)' at <std>:24062:15 calls 'std::io::sys_write'
  'c_write(fd, buf.as_ptr(), buf.len())' at <std>:23418:22 calls C's 'write'
warning query.program-errors: 1 error in the program; results may be incomplete
try: volec --diagnostics=short whybroken028/main.vl -c -o /dev/null
$ effects score --why alloc whybroken028/main.vl
crate::score	panic
  (not: alloc)
warning query.program-errors: 1 error in the program; results may be incomplete
try: volec --diagnostics=short whybroken028/main.vl -c -o /dev/null
$ effects scaled --why io whybroken028/main.vl
crate::scaled	io panic
  'clamp(x * 2)' at whybroken028/main.vl:7:5 calls 'clamp'
  'println("clamp {x}")' at whybroken028/main.vl:2:5 calls 'std::fmt::println'
  'write_erased::<W>' at <std>:17364:20 calls 'std::fmt::write_erased'
  'w.write_str(s)' at <std>:17956:5 calls 'IoOut::write_str'
  'self.inner.write_all(s.as_bytes())' at <std>:63153:19 calls 'Stdout::write_all'
  'fd_write_all(self.fd, buf)' at <std>:24676:9 calls 'std::io::fd_write_all'
  'sys_write(fd, buf)' at <std>:24062:15 calls 'std::io::sys_write'
  'c_write(fd, buf.as_ptr(), buf.len())' at <std>:23418:22 calls C's 'write'
warning query.program-errors: 1 error in the program; results may be incomplete
try: volec --diagnostics=short whybroken028/main.vl -c -o /dev/null
