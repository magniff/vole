# Float math (0.25.2.1), and integers' (0.25.2.2)

f32 and f64 have Rust's methods: `x.sqrt()`, `x.sin()`, `y.atan2(x)`,
`x.powi(2)`, `a.max(b)`, with no `use` (they are std::math's trait
`Float`, found as any trait's methods are). They are vole, not C: no
`unsafe`, no `import "math.h"`, the same results on every target; all
`#[pure]`.

```vole
fn main() -> i32 {
    let x = 2.0;
    let a: f32 = 0.5;
    println(f"{x.sqrt()} {a.sqrt()} {x.powi(10)} {x.powf(0.5)} {x.cbrt()}");
    let angle = f64::consts::PI / 6.0;
    println(f"{angle.sin():.3} {angle.cos():.3} {(1.0).atan2(-1.0)} {f64::consts::E.ln()}");
    println(f"{(-2.5).round()} {(2.5).round_ties_even()} {(-0.5).floor()} {(1.25).fract()}");
    println(f"{f64::NAN.max(1.0)} {(3.0).clamp(0.0, 1.0)} {(-0.0).signum()} {(3.0).hypot(4.0)}");
    println(f"{(0.0).ln()} {(-1.0).sqrt().is_nan()} {(90.0).to_radians()} {f32::EPSILON}");
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

A literal needs its type known for a method: `(2.0).sqrt()` is an
f64, `2.0f32.sqrt()` an f32; `let a: f32 = 0.5; a.sqrt()` too.

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
| `is_nan`, `is_finite`, `is_infinite`, `is_sign_positive`, `is_sign_negative` | tests |

The results are within 1 ulp of the exact value, or 2 (sqrt, the
rounding functions, min and max exact; powi a few more), with C99's
special values: `(0.0).atan2(-1.0)` is pi, `pow(x,
0.0)` is 1 even for NaN. f32's are f64's rounded once.

## Integers

The integer types (`i8` to `i64`, `u8` to `u64`) have Float's `abs`,
`signum`, `min(y)`, `max(y)`, `clamp(lo, hi)`, and `pow(exp: u32)`, as
methods with no `use` (std::num's trait `Int`, 0.25.2.2). They wrap as
integers do: `i64::MIN.abs()` is `i64::MIN`, a `pow` past the type's
range wraps; `clamp` never panics (`lo > hi`: hi). std's functions
`std::min(a, b)`, `std::max`, `std::clamp(x, lo, hi)` (any `Ord`
type) and `std::abs(x)` (an i64) do the same.

```vole
fn main() -> i32 {
    let x: i64 = -7;
    let n: u32 = 3;
    let px: i32 = 300;
    println(f"{x.abs()} {x.signum()} {x.min(0)} {x.max(0)} {px.clamp(0, 255)} {(2).pow(10)} {n.pow(2)}");
    println(f"{std::max(x, 1)} {std::clamp(px, 0, 255)} {std::abs(x)}");
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
`f64::NAN`, and f32's; `f64::consts::PI` (`std::f64::consts::PI` too),
`TAU`, `E`, `SQRT_2`, `LN_2`, `LN_10`, `LOG2_E`, `LOG10_E`, `LOG2_10`,
`LOG10_2`, `FRAC_PI_2`, `FRAC_PI_3`, `FRAC_PI_4`, `FRAC_PI_6`,
`FRAC_PI_8`, `FRAC_1_PI`, `FRAC_2_PI`, `FRAC_2_SQRT_PI`,
`FRAC_1_SQRT_2`, for f32 too (`f32::consts::PI` is an f32). They are
literals: `const TURN: f64 = f64::consts::TAU;` works.

```vole
let half_turn: f32 = f32::consts::PI;
println(f"{half_turn} {f64::MAX > 1e308} {f64::MIN_POSITIVE:e}");
```
```out
3.1415927 true 2.2250738585072014e-308
```

## Functions

`std::math` has each method as a function over f32 and f64
(`math::sqrt(x)`, `math::atan2(y, x)`, `math::pow(x, y)`), and the
constants as f64s (`math::PI`, `math::TAU`, `math::E`, ...), for code
written C's way:

```vole
use std::math;
use std::math::{PI, sqrt};

fn main() -> i32 {
    let r: f32 = 2.0;
    println(f"{PI * 2.0 * 2.0} {sqrt(r)} {math::atan2(1.0, 1.0) * 4.0} {math::max(r, 3.0)}");
    0
}
```
```out
12.566370614359172 1.4142135 3.141592653589793 3
```

A program's own trait with one of these names for f64 or f32 (`impl
MyMath for f64 { fn sqrt(self) ... }`) now meets std's: `duplicate
method 'sqrt' for type 'f64'`; delete it and use std's.
