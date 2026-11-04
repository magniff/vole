# arith263: Rust's arithmetic, decision 6 (0.26.3)

## Verdict

Done, with one cost to watch. The checks are on at -O0 and off at -O1
and up, `--overflow-checks=on|off` overrides, `/ 0` and `MIN / -1` panic
at every level, and a shift past the bits panics with the checks on and
is masked by the type's bits with them off. That masking is new for 8-
and 16-bit operands: they used to take the amount modulo 32. Constants
follow the same rule (`arith.overflow`). std's integer API matches
rustc on every type's edge values (tests/run/num_int_ops_rust.vl). std's
own wrap sites use `wrapping_*`. compiler/src has 46 wrap-reliant sites,
listed below for 0.26.4. The bench at -O2 is within 1% of 0.26.2 (see
the report's numbers). The cost to watch: std's core grows by 5.6 KB
(IntWrapping's impls, needed by foldhash), and a hello world costs 1.03x.

## What worked

- The previous session's census tooling (VOLE_OVF_CENSUS at -O2): an
  overflowing site is noted once and the program goes on. That gave
  compiler/src's whole census, and std's sites in the std-heavy cases
  and the bench, in one pass each.
- One -O0 run of the whole suite found every test, example, transcript,
  book and guide block that relied on wrapping (106 failures), in one go.
- Rust as an oracle: tools/intops/twin.py writes the API case from its
  Rust twin's output, so EXPECT lines are not hand-computed.
- `edit patch` with several --old/--new pairs for std, and `query show
  '<std>:LINE'` to map a std panic position to its function.

## What cost time, ranked

1. The lazy sections. Each IntOverflow section NEEDS every INTOPS word,
   and Wrapping derives Clone/Eq/Hash. So one `wrapping_add` in a core
   hash pulled HashMap, the Swiss table and the iterators into the core
   (169 KB to 293 KB), and the suite refused to start. Splitting the six
   wrapping methods into a section of their own, with NEEDS set, fixed
   it. The first try, without NEEDS, made lazy std sections fail with
   "no method 'wrapping_sub'".
2. `volec test` compares -O0 with -O2, so every overflow in a property
   looked like "a compiler bug". Its builds, and reduce --differs, now
   turn the checks on at both levels.
3. The tests that pinned the old semantics (x / 0 == 0, narrow shifts
   modulo 32, wrapping LCGs). 56 cases get `--overflow-checks=off`, four
   were rewritten, and 17 examples moved to `wrapping_*`.
4. Budgets near their limits: std's core (168,933 of 168,960 bytes),
   `guide std --whole` (21,987 of 22,000), the core guide (10,250 of
   10,240).
5. `check` instructions vary by about 2% from run to run on a loaded
   machine, so the 1.02x share needs min-of-N on a quiet one.

## Never used

- `refactor` (no renames), `probe`, `reduce`.

## Fix list, in order (tagged)

1. [0.26.4, compiler/src] Move these wrap sites to `wrapping_*` (census:
   the compiler built at -O2 with `--overflow-checks=on` and
   VOLE_OVF_CENSUS, run over the suite's 2,828 compilations at -O0 and
   -O2, and over the self-compile; positions as of this branch). Then
   drop `--overflow-checks=off` from bootstrap/chain-diverse.sh's B2 and
   A2O0:
   - `back/codecache/hash.vl:34:13` (multiply, 2828 of 2,828 compilations): `let v = (h ^ x) * 0x9E3779B97F4A7C15;`
   - `back/emit/blocks.vl:375:21` (subtract, 1 of 2,828 compilations): `let range = int_key(cx.sw_values.data[n - 1], ty) - int_key(low, ty) + 1;`
   - `back/enc_arm64/mod.vl:298:43` (subtract, 21 of 2,828 compilations): `let run = if ones == 64 { -1 } else { (1 << ones) - 1 };`
   - `back/isel/divisions.vl:163:25` (subtract, 1 of 2,828 compilations): `let ad = if d < 0 { (0 - d) as u64 } else { d as u64 };`
   - `back/isel/divisions.vl:233:17` (subtract, 2 of 2,828 compilations): `magic = 0 - magic;`
   - `back/isel/divisions.vl:248:47` (subtract, 1017 of 2,828 compilations): `let nc: u64 = 0xffffffffffffffff as u64 - (0 - d) % d;`
   - `back/isel/divisions.vl:258:18` (multiply, 1 of 2,828 compilations): `q1 = 2 * q1 + 1;`
   - `back/isel/divisions.vl:259:18` (multiply, 1017 of 2,828 compilations): `r1 = 2 * r1 - nc;`
   - `back/isel/divisions.vl:261:18` (multiply, 1 of 2,828 compilations): `q1 = 2 * q1;`
   - `back/isel/divisions.vl:274:18` (multiply, 1015 of 2,828 compilations): `q2 = 2 * q2;`
   - `back/isel/tiling.vl:372:20` (, 1 of 2,828 compilations): `if (mask & (mask + 1)) != 0 {`
   - `back/isel/tiling.vl:375:22` (, 1 of 2,828 compilations): `let n = log2(mask + 1);`
   - `back/objfile/assemble.vl:157:18` (subtract, 6 of 2,828 compilations): `if neg { 0 - v as i64 } else { v as i64 }`
   - `back/objfile/mod.vl:352:22` (multiply, 2343 of 2,828 compilations): `var h: u64 = n as u64 * 0x9e3779b97f4a7c15;`
   - `back/objfile/mod.vl:358:17` (multiply, 2344 of 2,828 compilations): `h = (h ^ w) * 0xff51afd7ed558ccd;`
   - `back/objfile/mod.vl:369:13` (multiply, 2343 of 2,828 compilations): `h = (h ^ w) * 0xff51afd7ed558ccd;`
   - `base/mod.vl:402:21` (subtract, 13 of 2,828 compilations): `buf_uint(b, (0 - value) as u64);`
   - `base/mod.vl:527:9` (multiply, 2828 of 2,828 compilations): `h *= 1099511628211;`
   - `front/consteval.vl:203:22` (subtract, 25 of 2,828 compilations): `wrap_int(0 - value, ty)` (a negative literal of a signed MIN, `-9223372036854775808`)
   - `front/cpp/eval.vl:224:28` (subtract, 14 of 2,828 compilations): `return (ev_convert(0 - v, p), p);`
   - `front/generics/mod.vl:399:13` (multiply, 2416 of 2,828 compilations): `h = (h ^ tmpl as u64) * 1099511628211;`
   - `front/generics/mod.vl:401:17` (multiply, 2416 of 2,828 compilations): `h = (h ^ TSCRATCH.data[i] as u64) * 1099511628211;`
   - `front/types.vl:128:13` (multiply, 2816 of 2,828 compilations): `h = (h ^ (kind as i64) as u64) * 1099511628211;`
   - `front/types.vl:129:13` (multiply, 2816 of 2,828 compilations): `h = (h ^ a as u64) * 1099511628211;`
   - `front/types.vl:130:13` (multiply, 2816 of 2,828 compilations): `h = (h ^ b as u64) * 1099511628211;`
   - `front/types.vl:131:13` (multiply, 2816 of 2,828 compilations): `h = (h ^ count as u64) * 1099511628211;`
   - `front/types.vl:133:17` (multiply, 2816 of 2,828 compilations): `h = (h ^ elems[i] as u64) * 1099511628211;`
   - `middle/fold/arch.vl:239:48` (multiply, 1 of 2,828 compilations): `Op::Mul => become_splat(cx, v, x * y),`
   - `middle/fold/arch.vl:296:30` (subtract, 1 of 2,828 compilations): `let lo = if signed { 0 - (1 << (bits - 1) as u64) } else { 0 };`
   - `middle/fold/arch.vl:297:30` (subtract, 1 of 2,828 compilations): `let hi = if signed { (1 << (bits - 1) as u64) - 1 } else { (1 << bits as u64) - `
   - `middle/fold/mod.vl:124:29` (add, 15 of 2,828 compilations): `Add => wrap_int(a + b, ty),`
   - `middle/fold/mod.vl:125:29` (subtract, 11 of 2,828 compilations): `Sub => wrap_int(a - b, ty),`
   - `middle/fold/mod.vl:126:29` (multiply, 46 of 2,828 compilations): `Mul => wrap_int(a * b, ty),`
   - `middle/fold/mod.vl:137:29` (subtract, 2 of 2,828 compilations): `Neg => wrap_int(0 - a, ty),`
   - `middle/fold/mod.vl:412:56` (add, 3 of 2,828 compilations): `let operand = const_before(cx, v, wrap_int(cx.insts[cx.insts[a].b].imm + c, ty),`
   - `middle/gvn.vl:102:21` (multiply, 102 of 2,828 compilations): `h = (h ^ ir_arg(cx, v, i) as u64) * 1099511628211;`
   - `middle/gvn.vl:91:13` (multiply, 1316 of 2,828 compilations): `h = (h ^ cx.insts[v].op as u64) * 1099511628211;`
   - `middle/gvn.vl:92:13` (multiply, 1312 of 2,828 compilations): `h = (h ^ cx.insts[v].cond as u64) * 1099511628211;`
   - `middle/gvn.vl:93:13` (multiply, 1312 of 2,828 compilations): `h = (h ^ cx.insts[v].ty as u64) * 1099511628211;`
   - `middle/gvn.vl:94:13` (multiply, 1313 of 2,828 compilations): `h = (h ^ cx.insts[v].a as u64) * 1099511628211;`
   - `middle/gvn.vl:95:13` (multiply, 1312 of 2,828 compilations): `h = (h ^ cx.insts[v].b as u64) * 1099511628211;`
   - `middle/gvn.vl:96:13` (multiply, 1312 of 2,828 compilations): `h = (h ^ cx.insts[v].c as u64) * 1099511628211;`
   - `middle/gvn.vl:97:13` (multiply, 1312 of 2,828 compilations): `h = (h ^ cx.insts[v].imm as u64) * 1099511628211;`
   - `middle/gvn.vl:98:13` (multiply, 1312 of 2,828 compilations): `h = (h ^ cx.insts[v].imm2 as u64) * 1099511628211;`
   - `middle/lower/ssa.vl:18:21` (multiply, 2778 of 2,828 compilations): `var slot = ((key as u64 * 11400714819323198485) >> 20) as i64 & mask;`
   - `places/build.vl:1824:21` (add, 1 of 2,828 compilations): `let count = int_key(NODES[p].y, t) - int_key(NODES[p].x, t) + 1;`
   Not reached by the census but wrap-reliant, new in this branch:
   middle/fold `fold_overflow`'s 64-bit `a + b`, `a - b` and `(a * b) / a`
   (reached from front/consteval's const_overflow with the checks on).
2. [std] std's own wrap sites written `wrapping_*` (61 calls in 31
   functions): match_tag_swar, hash_mix, fold_mul, fold_bytes_long,
   SipHasher13::round, sqrt64, atan2_64, wide_mul, num_is_8digits,
   num_parse_8digits, num_parse_digits_u64, num_parse_i64_from,
   num_round_to_odd64, num_take_digits, num_take_19digits,
   num_parse_number, num_compute_float, num_parse_decimal,
   splitmix64_next, Xoshiro256pp::{next_u64, random_range_i64, below_u64},
   tls_key, tls_new_key, table_byte, count_ones, trailing_zeros,
   decimal_len, test_next, test_seed_of, fuzz_hash. A census of 1,804
   std-heavy cases and examples, and the 43 bench programs, with the
   checks on finds no other std site, except `Int::abs` of a MIN,
   which panics as Rust's does.
3. [lang] `let x: u8 = 255 + 1` in a function body panics at run time
   with the checks on, where Rust rejects it at compile time
   (arithmetic_overflow). Only const items, statics, array lengths and
   discriminants are folded with the error.
4. [std, budget] The IntWrapping section costs 5.6 KB in every program.
   A compiler intrinsic for the six wrapping methods would cost none.
5. [tests] Of the 56 cases flagged `--overflow-checks=off`, most only
   wrap in their own LCG or checksum. 0.26.4 could move those to
   `wrapping_*` and keep the flag for the ones about wrapping.
6. [tools] `volec test` builds with the checks on at both levels. A
   program that wants wrapping writes `wrapping_*`; there is no
   `volec test --overflow-checks=off` yet.
