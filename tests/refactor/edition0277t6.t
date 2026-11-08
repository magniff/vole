## fix --edition rust (0.27.7, T6): edit_int_generic through a shift's
## left operand, and an operator's whose right operand is literals, to a
## method call's receiver: the leftmost literal gets MVS's i64. Written,
## formatted, then built and run in the rust edition with the MVS
## program's output; the rustc twin agrees (rust_t_literal_receiver).
$ main.vl -o mvs
ok: built mvs
% ./mvs
1099511627775 9223372036854775807 25 -7
$ fix --edition rust --list-left main.vl
fixed, 5 integers annotated	main.vl	+5 -4 lines
$ fmt main.vl
note fmt.none: 1 file formatted already
% cat main.vl
// fix --edition rust (0.27.7, T6): a method of an integer type called on
// a tree of literals, `(1 << n).wrapping_sub(1)`, gets its leftmost literal
// suffixed with MVS's i64, `(1i64 << n)`: in the rust edition the
// literal has no type there (rustc E0689, vole's type.infer), and i32's
// method would make 1 << 40 into 1 << 8. Through a shift's left operand
// and an operator whose right operand is literals too, `(2 + 3).pow(2)`.
fn run(ones: i64) -> i64 {
    (1i64 << ones).wrapping_sub(1)
}

fn main() {
    let a = run(40);
    let b = (1i64 << (a & 63) as u64).wrapping_sub(1);
    let c = (2i64 + 3).pow(2u32);
    let d = (0i64 - 1).wrapping_mul(7);
    println("{} {} {} {}", a, b, c, d);
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
1099511627775 9223372036854775807 25 -7
