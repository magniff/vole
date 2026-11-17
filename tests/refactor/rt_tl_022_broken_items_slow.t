## XFAIL: RT-TL-22: reading a file of broken items costs 0.65 ms each, and unclosed nested modules quadratic time (open)
## The program is written here: 6250 `mod m { ` never closed (50 KB) and
## 8000 broken fn headers (`fn fI( x`, 85 KB). The front end refuses
## them (right) but takes 9.7 s and about 5.4 s, all in "read, lex and modules"
## (--time-passes); 200 KB of `mod m { ` takes 97 s, of `fn f( ` 26 s. A
## well-formed file of 8000 functions checks in 0.15 s. Each must be
## refused within 2 s of CPU.
% python3 -c "open('jm.vl','w').write('mod m { '*6250 + '\nfn main() -> i32 { 0 }\n')" && (ulimit -t 2; volec check jm.vl >/dev/null 2>&1; echo "exit $?")
exit 1
% python3 -c "open('jg.vl','w').write(''.join('fn f%d( x\n' % i for i in range(8000)) + 'fn main() -> i32 { 0 }\n')" && (ulimit -t 2; volec check jg.vl >/dev/null 2>&1; echo "exit $?")
exit 1
