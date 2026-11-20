## XFAIL: RT-95: volec fmt rewrites a file that does not parse (`-> <<T as A>::B` becomes `-><<T as A>::B`) and exits 0 (0.30.2)
## fmt of a file with a parser error must refuse it and leave it as it
## is: its layout is a guess over tokens the parser did not accept. Seen
## while committing RT-93's case, whose `-> <<` and `= <<` fmt joined.
% volec fmt main.vl > out.txt 2>&1; echo "exit $?"; grep -c '^formatted' out.txt
exit 1
0
% head -1 main.vl
fn f() -> <<i64 as Tr>::Out as Tr>::Out {
