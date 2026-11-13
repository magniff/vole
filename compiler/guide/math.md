# Float math (0.25.2.1), and integers' (0.25.2.2)

Before writing a numeric helper, try `volec query items std --find
NAME`: `--find clamp` lists `f64::clamp`, `i64::clamp` and the rest,
`--find PI` the constants (`std::f64::consts::PI`); `--names` gives a line
each.

f32 and f64 have Rust's methods: `x.sqrt()`, `x.sin()`, `y.atan2(x)`,
`x.powi(2)`, `a.max(b)`, with no `use`. They are vole, not C: no
`unsafe`, no `import "math.h"`, the same results on every target.
There is no `std::math` of functions: the methods are the way, and the
constants are `std::f64::consts`'s.

```vole
fn main() -> i32 {
    let x = 2.0f64;
    let a: f32 = 0.5;
    println("{} {} {} {} {}", x.sqrt(), a.sqrt(), x.powi(10), x.powf(0.5), x.cbrt());
    let angle = std::f64::consts::PI / 6.0;
    println("{:.3} {:.3} {} {}", angle.sin(), angle.cos(), 1.0f64.atan2(-1.0), std::f64::consts::E.ln());
    println("{} {} {} {}", (-2.5f64).round(), 2.5f64.round_ties_even(), (-0.5f64).floor(), 1.25f64.fract());
    println("{} {} {} {}", f64::NAN.max(1.0), 3.0f64.clamp(0.0, 1.0), (-0.0f64).signum(),
        3.0f64.hypot(4.0));
    println("{} {} {} {}", 0.0f64.ln(), (-1.0f64).sqrt().is_nan(), 90.0f64.to_radians(), f32::EPSILON);
    0
}
```
```out
1.4142135623730951 0.70710677 1024 1.4142135623730951 1.2599210498948732
0.500 0.866 2.356194490192345 1
-3 2 -1 0.25
1 1 -1 5
-inf true 1.5707963267948966 0.00000011920929
```

A literal needs its type said for a method, as in Rust:
`2.0f64.sqrt()`, `2.0f32.sqrt()`, `(-2.5f64).round()`; `let a: f32 =
0.5; a.sqrt()` too.

## The methods

| method | is |
|---|---|
| `abs`, `signum`, `copysign(s)` | `\|x\|`; 1.0 or -1.0 by the sign bit (NaN for NaN); `\|x\|` with the sign of s |
| `floor`, `ceil`, `trunc`, `fract` | toward -inf, +inf, 0; `x - x.trunc()` |
| `round`, `round_ties_even` | half-way cases away from zero; to even |
| `min(y)`, `max(y)`, `clamp(lo, hi)` | NaN loses (`NAN.min(1.0)` is 1); `-0.0 < 0.0`; clamp keeps NaN, never panics |
| `sqrt`, `cbrt`, `hypot(y)` | square root (correctly rounded), cube root, `sqrt(x^2 + y^2)` without overflow |
| `sin`, `cos`, `tan`, `sin_cos` | radians, any size (`(1e300).sin()` is exact to 1 ulp); `sin_cos` returns both |
| `asin`, `acos`, `atan`, `atan2(x)` | inverses; `y.atan2(x)` is C's `atan2(y, x)` |
| `exp`, `exp2`, `ln`, `log2`, `log10`, `log(b)` | e^x, 2^x, the logarithms (`ln(0)` is -inf, below 0 NaN) |
| `powf(y)`, `powi(n: i32)` | x^y as C's pow; x^n by repeated squaring (faster, a few ulp) |
| `recip`, `to_radians`, `to_degrees` | 1/x; the angle conversions |
| `next_up`, `next_down` | (0.25.5) the neighbouring number above, below (by the bits: `0.0.next_up()` is the least subnormal, `f64::MAX.next_up()` inf) |
| `is_nan`, `is_finite`, `is_infinite`, `is_sign_positive`, `is_sign_negative` | tests |

The results are within 1 ulp of the exact value, or 2 (sqrt, the
rounding functions, min and max exact; powi a few more), with C99's
special values: `(0.0).atan2(-1.0)` is pi, `pow(x,
0.0)` is 1 even for NaN. f32's are f64's rounded once.

## Integers

The integer types (`i8` to `i64`, `u8` to `u64`) have `abs`,
`signum`, `min(y)`, `max(y)`, `clamp(lo, hi)`, `pow(exp: u32)` and
`unsigned_abs`, as methods with no `use` (a literal's type said:
`2i64.pow(10)`, rustc's E0689 otherwise). They overflow
as the operators do (0.26.3): `i64::MIN.abs()` and a `pow` past the
type's range panic with the overflow checks on (-O0) and wrap with them
off; `wrapping_abs`, `checked_pow`, `saturating_pow` and the rest
(`guide types#numbers`) choose at every level. `clamp` never panics
(`lo > hi`: hi). `std::cmp::min(a, b)` and `std::cmp::max` take any
`Ord` type.

```vole
use std::cmp;

fn main() -> i32 {
    let x: i64 = -7;
    let n: u32 = 3;
    let px: i32 = 300;
    println("{} {} {} {} {} {} {}", x.abs(), x.signum(), x.min(0), x.max(0), px.clamp(0, 255),
        2i64.pow(10), n.pow(2));
    println("{} {} {}", cmp::max(x, 1), cmp::min(px, 255), x.unsigned_abs());
    0
}
```
```out
7 -1 -7 0 255 1024 9
1 255 7
```

## Constants

Rust's names, as `i64::MAX` is: `f64::EPSILON`, `f64::MAX`,
`f64::MIN`, `f64::MIN_POSITIVE`, `f64::INFINITY`, `f64::NEG_INFINITY`,
`f64::NAN`, and f32's; `std::f64::consts::PI` (a path: `use
std::f64::consts` is not read yet),
`TAU`, `E`, `SQRT_2`, `LN_2`, `LN_10`, `LOG2_E`, `LOG10_E`, `LOG2_10`,
`LOG10_2`, `FRAC_PI_2`, `FRAC_PI_3`, `FRAC_PI_4`, `FRAC_PI_6`,
`FRAC_PI_8`, `FRAC_1_PI`, `FRAC_2_PI`, `FRAC_2_SQRT_PI`,
`FRAC_1_SQRT_2`, for f32 too (`std::f32::consts::PI` is an f32). They
are literals: `const TURN: f64 = std::f64::consts::TAU;` works.

```vole
let half_turn: f32 = std::f32::consts::PI;
println("{half_turn} {} {:e}", f64::MAX > 1e308, f64::MIN_POSITIVE);
```
```out
3.1415927 true 2.2250738585072014e-308
```
