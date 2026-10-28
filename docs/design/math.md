# Float math in std (0.25.2.1)

Every agent of the 0.25.2 GPU eval (evals/tasks/0.25.2/*/ANALYSIS.md)
hand-wrote Taylor sin/cos and Newton sqrt, or called C's libm through
`unsafe`: std had no float math. 0.25.2.1 adds it, in vole, with no C
call and no `unsafe` (the bit casts are std::num's `f64_to_bits` and
kin).

## Where it lives

- **Methods, as Rust spells them**: `x.sqrt()`, `x.sin()`,
  `y.atan2(x)`, `a.min(b)`, `x.powi(3)`. The language has no inherent
  impls on primitives (`impl f64 { }` is an error), but a trait can be
  implemented for them and its methods are found without a `use`: std
  has `pub trait std::math::Float` with `impl Float for f64` and
  `impl Float for f32`. `f64::sqrt(x)` works too (a path to the trait's
  method).
- **Functions**: `std::math::{sqrt, sin, ...}`, generic over `Float`
  (`math::sqrt(2.0)` is an f64, `math::sqrt(x)` of an f32 an f32), for
  code written C's way.
- **Constants**: Rust's names, built into the compiler as `i64::MAX` is
  (0.15): `f64::EPSILON`, `MAX`, `MIN`, `MIN_POSITIVE`, `INFINITY`,
  `NEG_INFINITY`, `NAN` (and f32's), and `f64::consts::PI` (`TAU`, `E`,
  `SQRT_2`, `LN_2`, `LN_10`, `FRAC_PI_2`, ...; also
  `std::f64::consts::PI`). `std::math::PI` (and the other math
  constants) are the f64 ones, for a `use`.

A cost of the trait: two impls of one method name for one type are an
error, so a program's own `impl MyExt for f64 { fn sqrt(self) ... }`
now conflicts with std's (the error names both; delete one). No test,
example or eval program had one.

## The functions

`abs signum copysign is_nan is_finite is_infinite is_sign_positive
is_sign_negative floor ceil round round_ties_even trunc fract min max
clamp recip to_radians to_degrees sqrt cbrt hypot sin cos tan sin_cos
asin acos atan atan2 exp exp2 ln log2 log10 log powf powi`, for f32 and
f64, Rust's semantics: `min`/`max` return the other argument when one
is NaN; `clamp` does not panic (NaN stays NaN); `round` rounds half
away from zero; `powi` multiplies by squaring (compiler-rt's
`__powidf2`, what Rust's powi is). All are `#[pure]`: no allocation,
no I/O, no globals.

## Algorithms

- f64: ports of FreeBSD's msun / musl (fdlibm, Sun Microsystems, 1993:
  "Permission to use, copy, modify, and distribute this software is
  freely granted, provided that this notice is preserved"), as the Rust
  `libm` crate has them: `__rem_pio2` (Cody-Waite in up to three
  steps) and `__kernel_rem_pio2` (Payne-Hanek with 2/pi's bits) for the
  trigonometric functions' argument reduction, the `__sin`/`__cos`/
  `__tan` kernels, e_asin/e_acos/s_atan/e_atan2, e_exp, e_log/e_log2/
  e_log10, e_pow, s_cbrt, musl's hypot (Dekker's exact squares).
- sqrt: correctly rounded, in integers: an estimate from a Newton
  iteration for 1/sqrt in f64 (no division), then the exact rounding
  decision from the 128-bit square of the candidate (std::num's
  `wide_mul`), so the result is the nearest f64 whatever the estimate's
  last bits. std::arch has no scalar square root (`_mm_sqrt_pd` only,
  x86-64), so the hardware instruction is not used.
- exp2(x): `2^k * exp(r * ln 2)`, k the nearest integer, r = x - k
  exact.
- floor, ceil, trunc, round: on the bits, exact.
- f32: computed in f64 and rounded once (f32 in, f64's few-ulp error,
  then one rounding): within 1 ulp, most of them correctly rounded;
  sqrt is exact (f64 has more than 2*24+2 bits).

Accuracy is checked against the system's libm (tests/run/math_vs_libm:
many inputs per function, the max ulp error printed and bounded) and
the special values (NaN, +-0, +-inf, subnormals, the edges of each
domain) are checked one by one (tests/run/math_special.vl).

## Loading

std's sections are read only when a program reaches them
(compiler/std/index.awk): std::math's are lazy, read when a program
names a method (`sqrt`, `sin`, ...: the trait section's TRIGGERS) or a
function, constant or `Float`.
