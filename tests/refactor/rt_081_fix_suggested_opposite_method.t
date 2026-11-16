## XFAIL: RT-81: fix --suggested applies a did-you-mean that is another operation: leading_ones to leading_zeros, trailing_ones to trailing_zeros, next_power_of_two to is_power_of_two, asinh to asin (0.30.2)
## The program is valid Rust (rustc prints `0 1`, `8`, `1.6472311463710958`)
## using four std methods vole lacks. Each error's help is a did-you-mean
## of one candidate, and `fix --suggested` ("the errors' exact fixes")
## applies all four: the program then checks and prints `29 0`, `false`,
## `NaN`. A near name that is a different operation (the complement, a
## predicate for a value, the inverse sine for the inverse hyperbolic
## sine) is no exact fix: it must not be applied (`sinh`, `rem_euclid`,
## `abs_diff` get a list of the nearest or a note, and nothing written).
$ fix --suggested
note fix.none: nothing to fix
% cat main.vl
fn main() {
    let x: u32 = 5;
    let y: f64 = 2.5;
    println("{} {}", x.leading_ones(), x.trailing_ones());
    println("{}", x.next_power_of_two());
    println("{}", y.asinh());
}
