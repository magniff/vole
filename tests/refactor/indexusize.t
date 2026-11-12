## (0.28.0, F20.8; tests/refactor/indexusize/) An index is a usize: the
## error's fix is the conversion, which `fix --suggested` makes, of an
## i64 too (out of range as an index before the conversion and after
## it, so no value's meaning changes; elsewhere an `as` that would wrap
## is refused, suggested.t): `n as usize`, an operation in parentheses,
## a range's end, and of an index that is a cast of an integer the
## cast's own type.
$ check
main.vl:2:9: error[type error] an index is a 'usize', got 'i64' | help: indexing takes a usize alone, as Rust's (no other integer type, no widening): convert it, or give the variable the type usize where it is declared | try: (b >> 4) as usize | try: volec fix --suggested main.vl
main.vl:7:18: error[type error] an index is a 'usize', got 'i64' | help: indexing takes a usize alone, as Rust's (no other integer type, no widening): convert it, or give the variable the type usize where it is declared | try: from as usize | try: volec fix --suggested main.vl
main.vl:10:14: error[type error] an index is a 'usize', got 'i32' | help: indexing takes a usize alone, as Rust's (no other integer type, no widening): convert it, or give the variable the type usize where it is declared | try: n as usize | try: volec fix --suggested main.vl
main.vl:17:27: error[type error] an index is a 'usize', got 'u8' | help: indexing takes a usize alone, as Rust's (no other integer type, no widening): convert it, or give the variable the type usize where it is declared | try: k as usize | try: volec fix --suggested main.vl
[exit 1]
$ fix --suggested --show
fixed 5 suggested fixes	main.vl	+4 -4 lines
// main.vl:2
2	    hex[(b >> 4) as usize]
// main.vl:7
7	    for x in &xs[from as usize..] {
// main.vl:10
10	    sum + xs[n as usize] + xs[(from + 1) as usize]
// main.vl:17
17	    println("{} {} {}", a[k as usize], digit(b"0123456789abcdef", 0x4f), wide);
$ check
ok: 0 errors in main.vl
% volec main.vl -o prog && ./prog
3 52 13
ok: built prog
