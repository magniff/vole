# superpi

π to any number of decimal digits, in one vole file: a small clone of the
Super PI benchmark, with the series the modern record computations use
rather than Super PI's own Gauss–Legendre iteration.

```sh
volec run examples/algorithms/superpi/main.vl -- 1000     # 1000 digits
volec examples/algorithms/superpi/main.vl -o superpi
./superpi 1000000                                         # a million digits, ~0.15 s
./superpi                                                 # default: 1000
./superpi 500 --no-check                                  # skip the cross-check
./superpi 100000 --check                                  # force the (quadratic) cross-check
./superpi 1000000 --threads 1                             # on one core, ~0.5 s
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

The split does not go down to single terms: a range of 16 or fewer is
built term by term, `P' = P p_k`, `Q' = Q q_k`, `T' = T q_k ± P' (A + B
k)`, where every factor fits a machine word, so a leaf is a few passes
of limb-by-word multiplies in place and enters no product routine. The
root of the split does not compute `P`, which only a parent would use.

**Limbs in base 10^9.** A limb product fits a `u64`, and each limb prints
as nine decimal digits. Schoolbook products accumulate rows in `u64`
columns; Karatsuba takes over at 128 limbs.

**Products by NTT from 256 limbs.** A product is a convolution, and the
number theoretic transform evaluates it in O(n log n) butterflies. Three
primes below 2^30 (469762049, 167772161, 754974721) with a factor of at
least 2^24 in `p - 1` give transforms of up to 2^24 points, and their
product exceeds every coefficient. Every modular value fits a `u32` and
every product a `u64`, so no 128-bit arithmetic is needed. A product up
to three times longer on one side is still one transform; beyond that
the long operand is cut into pieces.

The transform is the part that was made fast, and each choice is
there for a measured reason:

- **No bit-reversal pass.** The forward transform runs its stages from
  the whole array down (decimation in frequency) and leaves the spectrum
  in bit-reversed order; the inverse runs them from pairs up (decimation
  in time) and takes that order back. A pointwise product does not care.
- **One table of roots per prime, for the whole run.** The roots are
  stored stage by stage (the stage of half `h` at `[h, 2h)`), so every
  stage reads a contiguous run, and the stages below the top do not
  depend on the transform's length: the table of the longest transform
  so far serves every shorter one, forward and inverse (the inverse
  uses the forward roots and its result is read at index `(n - i) mod
  n`). The table is in an `Engine` that the products share, behind an
  `RwLock`.
- **Four butterflies a step in NEON** (`std::arch::aarch64`, 128-bit
  registers of four `u32` lanes), two stages in one pass over the array
  (radix 4), and a kernel of its own for the stages of blocks of 4 and
  2, which regroups the lanes by `zip`/`uzp`. The Montgomery product
  (`R = 2^32`) is two lanewise multiplies for the quotient, the widening
  `umull`/`umlsl` pairs for `a w - q p`, and one `uzp2` for the high
  halves: no division anywhere.
- **Lazy reduction.** `4p` fits a `u32`, so values stay in `[0, 2p)`
  forward and `[0, 4p)` inverse; the product's result, between `-p` and
  `p`, is used with `p` added, never compared. One `umin` a butterfly is
  left.
- **Montgomery constants on entry and exit.** An operand enters by one
  product by `R^2 mod p` (which also reduces the limb), the result
  leaves by one product by `1/n mod p`.
- **Garner without division.** The three residues are recombined by
  Garner's algorithm with Montgomery products by constants, and the
  exact coefficient plus carry is carried into base 10^9 by two `u64`
  divisions by the constant base, with no bignum per coefficient.

A square needs two transforms per prime, not three, and the split's
combine computes `P1 P2` with `P1 T2` and `Q1 Q2` with `T1 Q2`, so each
of those pairs shares one operand's forward transform. A scalar path
with the same arithmetic remains for machines without NEON
(`detect("neon")` chooses), and a test compares the two.

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

**Threads where there is independent work.** The `Engine` counts the
idle threads (the cores less the threads running); whoever has
independent work takes from the count and gives back at the join, so no
more threads run than there are cores and nothing is planned in advance.
The split gives its left half to a thread (ranges of 512 terms up); a
product runs two of its primes on threads and the third itself (from
2^13 points), and a prime its two forward transforms side by side;
Garner's reconstruction, whose coefficients are independent, is cut in
four with the pieces' carries added afterwards. The square root depends
on nothing in the series, so it runs beside the binary split, and the
final division's reciprocal depends only on T, so it runs beside the
numerator's root-times-Q product. `--threads N` sets the most threads
at once; `--threads 1` starts none. Threads are started for each piece
of work and joined: starting them was 0.2% of the samples, so a
persistent pool would win nothing.

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

- `volec test examples/algorithms/superpi/main.vl` runs eleven tests at
  -O0 and -O2: division against `u64` arithmetic on limb boundaries, the
  identity `q b + r = a` with `r < b` on random operands (including
  divisors just below a power of the base, which take the add-back path),
  NTT and Karatsuba products against schoolbook at and around the
  thresholds (squares and lopsided operands too), shared-operand pairs
  of products against schoolbook, the NEON transforms against the scalar
  butterflies for every prime (forward, inverse, and the inverse of the
  forward against the input), the leaves against the combine of single
  terms, the Newton division against algorithm D, exact integer square
  roots on squares and their neighbours up to 1000 limbs, the first
  hundred digits against the published expansion, and Chudnovsky against
  Machin at 200 and at 5000 digits.
- The whole expansion was compared digit for digit with an independent
  Python `decimal` Machin computation at 1000 and at 10000 digits:
  identical, including the last digit.

## Cost, measured

Times on an Apple M-series machine (4 performance and 6 efficiency
cores), `volec -O2`, for the Chudnovsky answer alone (the Machin
cross-check is extra where it runs), the fastest of several runs with
other work on the machine (1-minute load about 3):

| digits | all cores | `--threads 1` | instructions | what dominates |
|---|---|---|---|---|
| 1000 | 0.6 ms | | | the leaves and schoolbook products |
| 10000 | 3 ms | | 88 M | Karatsuba and the first NTTs |
| 100000 | 16 ms | 42 ms | 1.0 G | NTT products |
| 1000000 | 135-165 ms | 0.51 s | 11.9 G | the same, transform length 2^19 |
| 10000000 | 2.8 s | 9.5 s | | the same, transform length 2^22 |

A million digits took 0.79 s and 50.3 G instructions before the
transform was reworked (two butterflies a step in 64-bit registers,
twiddles gathered per stage, a bit-reversal pass, `% p` per element on
entry and exit, the split on one core); programs built on GMP take
0.25 to 0.4 s on one core of comparable hardware.

The Machin cross-check adds 0.7 ms at 1000 digits and 63 ms at 10000;
that is why it stops there. Every stage is linearithmic in the number of
digits, so these grow at a little worse than linearly. Nothing in the
computation uses floating point. What is left, in the order it would
pay: short products (the Newton steps discard half to two-thirds of the
limbs of each product they compute, and a middle-product NTT would
recover that), removing the common factors of P and Q during the split
(the GMP programs' trick, 20 to 30% at large sizes), and buffers kept
between products instead of allocated per transform. Replacing the three
primes with a floating point FFT is a much larger change, and its
correctness would rest on rounding analysis rather than on exact modular
arithmetic.
