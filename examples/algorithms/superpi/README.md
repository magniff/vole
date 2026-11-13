# superpi

π to any number of decimal digits, in one vole file: a small clone of the
Super PI benchmark, with the series the modern record computations use
rather than Super PI's own Gauss–Legendre iteration.

```sh
volec run examples/algorithms/superpi/main.vl -- 1000     # 1000 digits
volec examples/algorithms/superpi/main.vl -o superpi
./superpi 1000000                                         # a million digits, ~2 s
./superpi                                                 # default: 1000
./superpi 500 --no-check                                  # skip the cross-check
./superpi 100000 --check                                  # force the (quadratic) cross-check
```

```text
$ ./superpi 100
superpi: 100 digits after the decimal point
3.1415926535 8979323846 2643383279 5028841971 6939937510
  5820974944 5923078164 0628620899 8628034825 3421170679
check: Machin 16*arctan(1/5) - 4*arctan(1/239) agrees on all 100 digits: true
```

Digits go to stdout in groups of ten, fifty to a line; timings go to
stderr. The digits are truncated, not rounded, so the last one is the
true digit of π and not a rounding of it.

## How it works

**Chudnovsky's series.** Each term is worth 14.18 digits:

```
1/pi = 12 sum_k (-1)^k (6k)! (13591409 + 545140134 k)
           / ((3k)! (k!)^3 640320^(3k + 3/2))
```

**Binary splitting.** A range `a..b` of terms is a triple `(P, Q, T)` of
big integers with `T/Q` the partial sum. One term has
`P = (6a-5)(2a-1)(6a-1)`, `Q = a^3 * 640320^3/24`, `T = P (A + B a)` with
the sign of `a`; two halves combine as

```
P = P1 P2,  Q = Q1 Q2,  T = T1 Q2 + P1 T2
```

so the sum costs a balanced tree of big products instead of one division
per term, and `pi = 426880 sqrt(10005) Q / T` at the end. Only `T` is
signed; the combine adds the two signed products by comparing
magnitudes.

**Limbs in base 10^9.** A limb product fits a `u64`, and each limb prints
as nine decimal digits. Schoolbook products accumulate rows in `u64`
columns; Karatsuba takes over at 96 limbs.

**Products by NTT above 512 limbs.** A product is a convolution, and the
number theoretic transform evaluates it in O(n log n) butterflies. Three
32-bit primes with primitive root 3 and a large power-of-two factor in
`p - 1` give transforms of up to 2^24 points; every modular value is
below 2^30, so no 128-bit arithmetic is needed. The butterflies use
Montgomery reduction with `R = 2^32` (three machine multiplies and a
shift, never a division), twiddles are precomputed a stage at a time, and
the three residues are recombined by Garner's algorithm into exact
coefficients, which are carried back into base 10^9 with plain `u64`
arithmetic — no bignum is allocated per coefficient. A square needs two
transforms per prime, not three. The butterflies themselves run two at a
time in NEON lanes (`std::arch::aarch64`): the operands are below 2^30,
so they live in u32 lanes, the widening `umull`/`umlal` multiplies do the
Montgomery reduction, and the modular add and subtract are u32 lanes
again. That also halves the transform arrays' memory traffic. A scalar
path remains for machines without NEON (`detect("neon")` chooses).

**Division and square root by Newton, with doubling precision.** The
reciprocal of the divisor is computed by Newton's iteration at a
precision that doubles each step (`R' = 2R - b R^2 / BASE^(2u)`), then
one product gives the quotient and a correction of at most a few units
makes it exact. The integer square root works the same way: the root of
the top 2t limbs, then one Newton step at 2u limbs. Both end with an
exact check against the operand (quotient times divisor, root squared),
and anything unexpected falls back to Knuth's algorithm D, so results are
exact by construction rather than by an error bound. Knuth D still does
the small divisions and is the reference the fast paths are tested
against.

**Threads where they pay.** The three primes of a large transform are
independent and run on three scoped threads (above 2^16 points; spawning
costs more than it saves below that). Two overlaps do the rest: the
square root depends on nothing in the series, so it runs beside the
binary split, and the final division's reciprocal depends only on T, so
it runs beside the numerator's root-times-Q product. Threading the
split's recursion as well was measured and made things worse: the
transform threads already use the cores.

**An independent cross-check.** Up to 10000 digits every run also
evaluates Machin's formula `pi = 16 arctan(1/5) - 4 arctan(1/239)` in
fixed point — a different series, no big division, no square root, only
divisors that fit one limb — and compares the two digit strings. A
disagreement is printed as `... : false` and the exit status is 1. It is
a real check: changing the final constant 426880 by one makes it fail.
Above 10000 digits it is skipped, because Machin is the only quadratic
part left and would cost far longer than the answer; `--check` forces it,
`--no-check` skips it everywhere.

## Verification

- `volec test examples/algorithms/superpi/main.vl` runs seven tests at
  -O0 and -O2: division against `u64` arithmetic on limb boundaries, the
  identity `q b + r = a` with `r < b` on random operands (including
  divisors just below a power of the base, which take the add-back path),
  NTT and Karatsuba products against schoolbook at and around the
  threshold (squares and lopsided operands too), the Newton division
  against algorithm D, exact integer square roots on squares and their
  neighbours up to 1000 limbs, the first hundred digits against the
  published expansion, and Chudnovsky against Machin at 200 digits.
- The whole expansion was compared digit for digit with an independent
  Python `decimal` Machin computation at 1000 and at 10000 digits:
  identical, including the last digit.

## Cost, measured

Times on an Apple M-series machine, `volec -O2`, for the Chudnovsky
answer alone (the Machin cross-check is extra where it runs):

| digits | time | what dominates |
|---|---|---|
| 1000 | 0.6 ms | schoolbook products |
| 10000 | 15 ms | Karatsuba and the first NTTs |
| 100000 | 0.19 s | NTT products, three threads |
| 1000000 | 1.5-2.1 s | the same, transform length 2^19 |

(The million-digit figure is the spread over several runs while other
work was on the machine; the best run was 1.42 s.)

The Machin cross-check adds 0.7 ms at 1000 digits and 72 ms at 10000;
that is why it stops there. Every stage is linearithmic in the number of
digits, so these grow at a little worse than linearly. Nothing in the
computation uses floating point. Getting a million digits under a second
from here means short products for the discarded halves of the Newton
steps (a middle-product NTT) and reusing forward transforms between the
products that share an operand in the split, not a different algorithm.
Both were left out: the first is a large, delicate change, the second
buys about a sixth of the split's transforms.
