#!/usr/bin/env python3
"""Writes compiler/std2/intconv.vl: the integers' TryFrom impls,
from_str_radix and std::num::Wrapping<T>, one of each per type, pair of types
or operator (vole has no macros;
Rust's std writes them with macro_rules). Run it after changing this
script; the file says it is generated.

usage: tools/std2-intconv.py [--check]   (--check: exit 1 when the file differs)
"""
import os
import sys

TOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(TOP, "compiler", "std2", "intconv.vl")

# name, signed, bits (usize and isize are 64 bits on every target)
TYPES = [("i8", True, 8), ("i16", True, 16), ("i32", True, 32), ("i64", True, 64),
         ("isize", True, 64), ("u8", False, 8), ("u16", False, 16), ("u32", False, 32),
         ("u64", False, 64), ("usize", False, 64)]


def lo(signed, bits):
    return -(1 << (bits - 1)) if signed else 0


def hi(signed, bits):
    return (1 << (bits - 1)) - 1 if signed else (1 << bits) - 1


def lit(v, name):
    # (the smallest i64 has no literal: -9223372036854775808 is the negation of one too large)
    if v == -(1 << 63):
        return f"{name}::MIN"
    return f"{v}{name}" if v >= 0 else f"-{-v}{name}"


WRAPPING_HEAD = """
// std::num::Wrapping<T> (0.28.0), as Rust's: an integer T whose `+`, `-`,
// `*`, `/`, `%`, unary `-` and shifts wrap at T's width instead of
// panicking (a shift's count is taken modulo the width; `/` and `%` by zero
// still panic); `!`, `&`, `|`, `^`; each with its assignment (`+=` takes a
// Wrapping<T> or a T); Display, Debug and the radix formats are T's; Sum
// and Product. The arithmetic is done on the value's 64 bits (__IntBits) and
// cut to T's width: one generic impl an operator, kept only by a program
// that names Wrapping. Not there: the impls for references (`&a + &b`), the
// constants MIN, MAX and BITS, to_be, to_le, from_be, from_le. abs, signum,
// is_positive and is_negative (Rust: signed T only) and is_power_of_two
// (Rust: unsigned T only) are there for every T.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub struct Wrapping<T>(pub T);

// T's width in bits, and the mask of its bits in 64.
#[effects()]
fn wrap_width<T: __IntBits>() -> (u64, u64) {
    let width = 8 * crate::mem::size_of::<T>() as u64;
    (width, if width == 64 { 0xffffffffffffffff } else { (1u64 << width) - 1 })
}

// T's value as its width's bits, zero-extended.
#[effects()]
fn wrap_bits<T: __IntBits>(x: T) -> u64 {
    let (_, mask) = wrap_width::<T>();
    x.__int_bits().0 & mask
}
"""

# trait, method, the 64-bit expression of a and b
WRAP_BINARY = [("Add", "add", "a.wrapping_add(b)"), ("Sub", "sub", "a.wrapping_sub(b)"),
               ("Mul", "mul", "a.wrapping_mul(b)"), ("BitAnd", "bitand", "a & b"),
               ("BitOr", "bitor", "a | b"), ("BitXor", "bitxor", "a ^ b")]
# trait, method, the signed (i64) expression, the unsigned one
WRAP_DIVIDE = [("Div", "div", "(a as i64).wrapping_div(b as i64) as u64", "a / b"),
               ("Rem", "rem", "(a as i64).wrapping_rem(b as i64) as u64", "a % b")]
WRAP_SHIFT = [("Shl", "shl", "a << s", "a << s"),
              ("Shr", "shr", "((a as i64) >> (s as i64)) as u64", "a >> s")]
WRAP_ASSIGN = [("AddAssign", "add_assign", "+"), ("SubAssign", "sub_assign", "-"),
               ("MulAssign", "mul_assign", "*"), ("DivAssign", "div_assign", "/"),
               ("RemAssign", "rem_assign", "%"), ("BitAndAssign", "bitand_assign", "&"),
               ("BitOrAssign", "bitor_assign", "|"), ("BitXorAssign", "bitxor_assign", "^")]
WRAP_FMT = ["Display", "Debug", "Binary", "Octal", "LowerHex", "UpperHex"]

WRAPPING_METHODS = """
// (the bit counts are u64's, whose list has `diverge`: its loops)
impl<T: __IntBits + Copy> Wrapping<T> {
    #[effects(diverge)]
    pub fn count_ones(self) -> u32 {
        wrap_bits(self.0).count_ones()
    }

    #[effects(diverge)]
    pub fn count_zeros(self) -> u32 {
        let (width, _) = wrap_width::<T>();
        width as u32 - wrap_bits(self.0).count_ones()
    }

    #[effects(diverge)]
    pub fn leading_zeros(self) -> u32 {
        let (width, _) = wrap_width::<T>();
        wrap_bits(self.0).leading_zeros() - (64 - width as u32)
    }

    #[effects(diverge)]
    pub fn trailing_zeros(self) -> u32 {
        let (width, _) = wrap_width::<T>();
        let m = wrap_bits(self.0);
        if m == 0 { width as u32 } else { m.trailing_zeros() }
    }

    // The bits turned left by n places (n modulo the width).
    #[effects()]
    pub fn rotate_left(self, n: u32) -> Wrapping<T> {
        let (width, _) = wrap_width::<T>();
        let m = wrap_bits(self.0);
        let s = n as u64 % width;
        Wrapping(T::__int_from(if s == 0 { m } else { (m << s) | (m >> (width - s)) }))
    }

    #[effects()]
    pub fn rotate_right(self, n: u32) -> Wrapping<T> {
        let (width, _) = wrap_width::<T>();
        let m = wrap_bits(self.0);
        let s = n as u64 % width;
        Wrapping(T::__int_from(if s == 0 { m } else { (m >> s) | (m << (width - s)) }))
    }

    // The bytes in the opposite order.
    #[effects()]
    pub fn swap_bytes(self) -> Wrapping<T> {
        let (width, _) = wrap_width::<T>();
        let mut m = wrap_bits(self.0);
        let mut r: u64 = 0;
        for _ in 0..width / 8 {
            r = (r << 8) | (m & 0xff);
            m >>= 8;
        }
        Wrapping(T::__int_from(r))
    }

    // The bits in the opposite order.
    #[effects()]
    pub fn reverse_bits(self) -> Wrapping<T> {
        let (width, _) = wrap_width::<T>();
        let mut m = wrap_bits(self.0);
        let mut r: u64 = 0;
        for _ in 0..width {
            r = (r << 1) | (m & 1);
            m >>= 1;
        }
        Wrapping(T::__int_from(r))
    }

    // self to the power exp, wrapping (by squaring).
    #[effects()]
    pub fn pow(self, exp: u32) -> Wrapping<T> {
        let mut base = self.0.__int_bits().0;
        let mut e = exp;
        let mut acc: u64 = 1;
        // (exp's 32 bits, the low one first)
        for _ in 0..32 {
            if e == 0 {
                break;
            }
            if (e & 1) == 1 {
                acc = acc.wrapping_mul(base);
            }
            base = base.wrapping_mul(base);
            e >>= 1;
        }
        Wrapping(T::__int_from(acc))
    }

    #[effects()]
    pub fn is_power_of_two(self) -> bool {
        let m = wrap_bits(self.0);
        m != 0 && (m & (m - 1)) == 0
    }

    // The absolute value; the smallest value of a signed T stays itself.
    #[effects()]
    pub fn abs(self) -> Wrapping<T> {
        let (a, signed) = self.0.__int_bits();
        if signed && (a as i64) < 0 { Wrapping(T::__int_from(0u64.wrapping_sub(a))) } else { self }
    }

    // -1, 0 or 1, as the value is negative, zero or positive.
    #[effects()]
    pub fn signum(self) -> Wrapping<T> {
        let (a, signed) = self.0.__int_bits();
        Wrapping(T::__int_from(if a == 0 { 0 }
            else if signed && (a as i64) < 0 { 0xffffffffffffffff }
            else { 1 }))
    }

    #[effects()]
    pub fn is_positive(self) -> bool {
        let (a, signed) = self.0.__int_bits();
        a != 0 && !(signed && (a as i64) < 0)
    }

    #[effects()]
    pub fn is_negative(self) -> bool {
        let (a, signed) = self.0.__int_bits();
        signed && (a as i64) < 0
    }
}
"""


def wrapping(w):
    for line in WRAPPING_HEAD.split("\n")[:-1]:
        w(line)
    for (tr, m, e) in WRAP_BINARY:
        w("")
        w(f"impl<T: __IntBits + Copy> crate::ops::{tr} for Wrapping<T> {{")
        w("    type Output = Wrapping<T>;")
        w("")
        w(f"    fn {m}(self, rhs: Wrapping<T>) -> Wrapping<T> {{")
        w("        let a = self.0.__int_bits().0;")
        w("        let b = rhs.0.__int_bits().0;")
        w(f"        Wrapping(T::__int_from({e}))")
        w("    }")
        w("}")
    for (tr, m, se, ue) in WRAP_DIVIDE:
        w("")
        w("// (by zero: a panic, as T's)")
        w(f"impl<T: __IntBits + Copy> crate::ops::{tr} for Wrapping<T> {{")
        w("    type Output = Wrapping<T>;")
        w("")
        w(f"    fn {m}(self, rhs: Wrapping<T>) -> Wrapping<T> {{")
        w("        let (a, signed) = self.0.__int_bits();")
        w("        let b = rhs.0.__int_bits().0;")
        w(f"        let q = if signed {{ {se} }} else {{ {ue} }};")
        w("        Wrapping(T::__int_from(q))")
        w("    }")
        w("}")
    for (tr, m, se, ue) in WRAP_SHIFT:
        w("")
        w(f"impl<T: __IntBits + Copy> crate::ops::{tr}<usize> for Wrapping<T> {{")
        w("    type Output = Wrapping<T>;")
        w("")
        w(f"    fn {m}(self, rhs: usize) -> Wrapping<T> {{")
        w("        let (width, _) = wrap_width::<T>();")
        w("        let (a, signed) = self.0.__int_bits();")
        w("        let s = rhs as u64 & (width - 1);")
        if se == ue:
            w(f"        Wrapping(T::__int_from({se}))")
        else:
            w(f"        let q = if signed {{ {se} }} else {{ {ue} }};")
            w("        Wrapping(T::__int_from(q))")
        w("    }")
        w("}")
    w("")
    w("impl<T: __IntBits + Copy> crate::ops::Neg for Wrapping<T> {")
    w("    type Output = Wrapping<T>;")
    w("")
    w("    fn neg(self) -> Wrapping<T> {")
    w("        Wrapping(T::__int_from(0u64.wrapping_sub(self.0.__int_bits().0)))")
    w("    }")
    w("}")
    w("")
    w("impl<T: __IntBits + Copy> crate::ops::Not for Wrapping<T> {")
    w("    type Output = Wrapping<T>;")
    w("")
    w("    fn not(self) -> Wrapping<T> {")
    w("        Wrapping(T::__int_from(!self.0.__int_bits().0))")
    w("    }")
    w("}")
    for (tr, m, op) in WRAP_ASSIGN:
        w("")
        w(f"impl<T: __IntBits + Copy> crate::ops::{tr} for Wrapping<T> {{")
        w(f"    fn {m}(&mut self, rhs: Wrapping<T>) {{")
        w(f"        *self = *self {op} rhs;")
        w("    }")
        w("}")
        w("")
        w(f"impl<T: __IntBits + Copy> crate::ops::{tr}<T> for Wrapping<T> {{")
        w(f"    fn {m}(&mut self, rhs: T) {{")
        w(f"        *self = *self {op} Wrapping(rhs);")
        w("    }")
        w("}")
    for (tr, m, op) in [("ShlAssign", "shl_assign", "<<"), ("ShrAssign", "shr_assign", ">>")]:
        w("")
        w(f"impl<T: __IntBits + Copy> crate::ops::{tr}<usize> for Wrapping<T> {{")
        w(f"    fn {m}(&mut self, rhs: usize) {{")
        w(f"        *self = *self {op} rhs;")
        w("    }")
        w("}")
    for tr in WRAP_FMT:
        w("")
        w(f"impl<T: crate::fmt::{tr}> crate::fmt::{tr} for Wrapping<T> {{")
        w("    fn fmt(&self, f: &mut crate::fmt::Formatter<'_>) -> crate::fmt::Result {")
        w(f"        crate::fmt::{tr}::fmt(&self.0, f)")
        w("    }")
        w("}")
    for (tr, m, start, op) in [("Sum", "sum", 0, "+"), ("Product", "product", 1, "*")]:
        w("")
        w(f"impl<T: __IntBits + Copy> crate::iter::{tr} for Wrapping<T> {{")
        w(f"    fn {m}<I: crate::iter::Iterator<Item = Wrapping<T>>>(iter: I) -> Wrapping<T> {{")
        w(f"        let mut acc = Wrapping(T::__int_from({start}));")
        w("        for x in iter {")
        w(f"            acc = acc {op} x;")
        w("        }")
        w("        acc")
        w("    }")
        w("}")
    for line in WRAPPING_METHODS.split("\n")[:-1]:
        w(line)


def main():
    out = []
    w = out.append
    w("// EDITION: rust")
    w("// Generated by tools/std2-intconv.py (do not edit): the integers' TryFrom")
    w("// impls and from_str_radix, which Rust's std writes with macros.")
    w("//")
    w("// `T::try_from(x)` of an integer x: Ok when x is one of T's values, else")
    w("// Err(TryFromIntError), as Rust's. A conversion that cannot fail (Rust has")
    w("// `From` for it, and Infallible for its TryFrom's error) has the error")
    w("// type TryFromIntError here too, and is always Ok: `{:?}` of a")
    w("// Result<T, Infallible> does not compile yet (its Err arm is refused as")
    w("// unreachable). usize and isize are 64 bits. One generic impl over a")
    w("// private trait of the ten types does it.")
    w("//")
    w("// `T::from_str_radix(s, radix)`: s as a T in radix (2 to 36, else a panic):")
    w("// an optional `+` (or `-`, for a signed type), then digits (`a`-`z` and")
    w("// `A`-`Z` are 10 to 35), nothing else; the errors are `s.parse::<T>()`'s.")
    w("")
    w("use crate::convert::{TryFrom, TryFromIntError};")
    w("use crate::result::Result;")
    w("use crate::str::{IntErrorKind, ParseIntError};")
    w("")
    w("// The value of s in radix, as its 64 bits (two's complement for a negative")
    w("// one): at most `pos` when positive, and, for a signed type, at most `neg`")
    w("// in magnitude when negative.")
    w("fn parse_radix(s: &str, radix: u32, signed: bool, pos: u64, neg: u64) -> Result<u64,")
    w("    ParseIntError> {")
    w("    if radix < 2 || radix > 36 {")
    w('        crate::panic::panic("from_str_radix: the radix must lie in the range `[2, 36]`");')
    w("    }")
    w("    let b = s.as_bytes();")
    w("    if b.len() == 0 {")
    w("        return Result::Err(crate::str::int_error(IntErrorKind::Empty));")
    w("    }")
    w("    let mut i: usize = 0;")
    w("    let mut negative = false;")
    w("    if b[0] == b'+' {")
    w("        i = 1;")
    w("    } else if b[0] == b'-' && signed {")
    w("        negative = true;")
    w("        i = 1;")
    w("    }")
    w("    if i == b.len() {")
    w("        return Result::Err(crate::str::int_error(IntErrorKind::InvalidDigit));")
    w("    }")
    w("    let limit = if negative { neg } else { pos };")
    w("    let r = radix as u64;")
    w("    let mut acc: u64 = 0;")
    w("    while i < b.len() {")
    w("        let c = b[i];")
    w("        let d: u64 = if c >= b'0' && c <= b'9' {")
    w("            (c - b'0') as u64")
    w("        } else if c >= b'a' && c <= b'z' {")
    w("            (c - b'a') as u64 + 10")
    w("        } else if c >= b'A' && c <= b'Z' {")
    w("            (c - b'A') as u64 + 10")
    w("        } else {")
    w("            36")
    w("        };")
    w("        if d >= r {")
    w("            return Result::Err(crate::str::int_error(IntErrorKind::InvalidDigit));")
    w("        }")
    w("        // (acc * r + d <= limit, without overflow: d < r <= 36 <= limit)")
    w("        if acc > (limit - d) / r {")
    w("            return Result::Err(crate::str::int_error(if negative { IntErrorKind::NegOverflow }")
    w("                else { IntErrorKind::PosOverflow }));")
    w("        }")
    w("        acc = acc * r + d;")
    w("        i += 1;")
    w("    }")
    w("    Result::Ok(if negative { (!acc).wrapping_add(1) } else { acc })")
    w("}")
    for (name, signed, bits) in TYPES:
        pos = hi(signed, bits)
        neg = -lo(signed, bits)
        w("")
        w(f"impl {name} {{")
        w("    #[effects(panic)]")
        w(f"    pub fn from_str_radix(src: &str, radix: u32) -> Result<{name}, ParseIntError> {{")
        w(f"        match parse_radix(src, radix, {'true' if signed else 'false'}, {pos}, {neg}) {{")
        w(f"            Result::Ok(v) => Result::Ok(v as {name}),")
        w("            Result::Err(e) => Result::Err(e),")
        w("        }")
        w("    }")
        w("}")
    w("")
    w("// What the one TryFrom impl below reads of an integer type: std's own.")
    w("// (Two one-line methods a type: the lazy std keeps these impls in every")
    w("// program. The type's range comes from its size and whether it is signed.)")
    w("pub trait __IntBits: Sized {")
    w("    // The value as 64 bits, sign-extended, and whether the type is signed.")
    w("    fn __int_bits(self) -> (u64, bool);")
    w("    // The value of its width's low bits of v.")
    w("    fn __int_from(v: u64) -> Self;")
    w("}")
    for (name, signed, bits) in TYPES:
        w("")
        w(f"impl __IntBits for {name} {{")
        if name == "u64":
            w("    fn __int_bits(self) -> (u64, bool) { (self, false) }")
        elif signed:
            w("    fn __int_bits(self) -> (u64, bool) { (self as i64 as u64, true) }")
        else:
            w("    fn __int_bits(self) -> (u64, bool) { (self as u64, false) }")
        w(f"    fn __int_from(v: u64) -> {name} {{ v{'' if name == 'u64' else ' as ' + name} }}")
        w("}")
    w("")
    w("// Every pair of integer types (one impl, not a hundred: the lazy std keeps")
    w("// an impl of a trait for a primitive type in every program).")
    w("impl<S: __IntBits, T: __IntBits> TryFrom<S> for T {")
    w("    type Error = TryFromIntError;")
    w("")
    w("    fn try_from(x: S) -> Result<T, TryFromIntError> {")
    w("        let (v, negative_kind) = x.__int_bits();")
    w("        // (T's range: is it signed? its -1 has the top bit of 64 set)")
    w("        let (_, signed) = T::__int_from(0).__int_bits();")
    w("        let width = 8 * crate::mem::size_of::<T>() as u64;")
    w("        // (its largest value: width - 1 ones when signed, width ones when not)")
    w("        let max: u64 = if signed { (1u64 << (width - 1)) - 1 }")
    w("            else if width == 64 { 0xffffffffffffffff }")
    w("            else { (1u64 << width) - 1 };")
    w("        if negative_kind && (v as i64) < 0 {")
    w("            // (its smallest: -(max + 1) when signed, 0 when not)")
    w("            if !signed || (v as i64) < -(max as i64) - 1 {")
    w("                return Result::Err(crate::convert::int_range_error(true));")
    w("            }")
    w("        } else if v > max {")
    w("            return Result::Err(crate::convert::int_range_error(false));")
    w("        }")
    w("        Result::Ok(T::__int_from(v))")
    w("    }")
    w("}")
    wrapping(w)
    text = "\n".join(out) + "\n"
    if "--check" in sys.argv[1:]:
        cur = open(OUT).read() if os.path.exists(OUT) else ""
        if cur != text:
            print("std2-intconv: compiler/std2/intconv.vl is not what tools/std2-intconv.py writes")
            sys.exit(1)
        return
    with open(OUT, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
