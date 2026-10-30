# numbers262: the session (steps 1 and 2)

## Verdict

Step 1's stop rule fires on every count, so the work stops there and
decision 6 goes back to the user. Over 43 programs (bench/*.vl and
bench/std/*.vl, text_gen left out because it is a module), at -O2 with the
prototype on against off:

- instructions retired: geomean 1.285, and 26 programs above 1.20 (the
  limits are 1.05 and none);
- vector loops: 34 of 113 lost, 30% (the limit is 25%). bench/vecloop
  loses all 5, at 3.50x instructions for vec.vl and 3.07x for raw.vl;
- Rust's twins under `-C overflow-checks=on` against off: geomean 1.005,
  at most 1.076 (chars).

The purecall ratio passes (78 ms against 79 ms).

Step 2 (float to integer `as` saturates, as Rust's) is done, and checked
at -O0 and -O2 on AArch64 and on x86-64 under Rosetta.

## Step 1's table

Columns: instructions off, on/off, best-of-5 ms off and on, `__text`
on/off, vector loops off>on, overflow checks left and removed (by ranges
or folding), and Rust's on/off where there is a twin.

```
program               insns off  on/off ms off  ms on   text   vec ovf left ovf rm rust on/off
arena_trees           700771817   1.290     40     40   1.38  0>0       104      6
binarytrees          5104079171   1.013    169    200   1.61  0>0        45      6
collatz              3041364472   1.421    338    391   2.67  0>0         3      0
contracts            6963409635   1.617    223    336   1.22  3>2       381     73
contracts_plain      6777283642   1.609    211    316   1.20  3>2       378     69
fannkuch             1284614394   1.267    122    123   1.33  0>0         6      1
fib                   282883814   0.987     15     12   1.78  0>0         9      0
fmtints               669097297   1.274     24     28   1.50  2>1        74     18
fmtloop               656105832   1.273     23     26   1.48  1>1       154     52
heap                 1732320908   1.623    222    252   1.51  0>0        39      0
interp               1500362731   1.403     49     57   1.38  0>0        18      0
iterchain            4473704772   3.885    217    542   1.15  3>1        46     15
iterloop             4505204709   3.672    247    522   1.08  3>1        37      8
json                 1455103821   1.226    109    113   1.38  1>1        69      2
mandelbrot           2175274211   0.999    175    174   1.54  0>0         1      1
matmul                248062831   1.000     19     19   0.79  1>1         0     12
nbody                 622417738   1.000     32     32   1.00  0>0         0      1
purecall             1128921493   1.000     79     78   1.73  0>0         3      0
purecall_hoisted     1116528152   1.000     78     79   1.50  0>0         3      0
sieve                 471047431   1.011     74     77   2.23  0>0         1      0
sort                  356812014   1.227     20     21   1.37  1>1       175    130
stencil               236112201   1.000      8      8   1.00  1>1         0      7
wordcount            1747987468   1.157    105    104   1.44  2>1       102     17
std_btree_u64        1324682135   1.059    234    234   1.34  0>0       107     39       1.005
std_chars            5039189315   1.450    270    318   1.35 10>7       261    158       1.076
std_fmt_f64           921567187   1.358     55     65   1.45  8>6       197    145       1.000
std_fmt_f64_prec     1716961737   1.009    107    109   1.42  8>6       225    148       1.000
std_fmt_int          2997212255   1.360    302    322   1.45  0>0        83     28       1.000
std_graphemes       22083398934   1.258   1023   1133   1.29 10>7       266    189       1.005
std_hash_churn       1028729338   1.463     84    100   1.61  2>1       156     34       1.012
std_hash_str         1342632732   1.410     78    116   1.56  2>1       183     36       1.011
std_hash_u64          582643016   1.359     57     60   1.62  2>1       158     34       1.018
std_parse_f64        6247154771   1.341    182    233   1.48  4>3       209     76       1.002
std_parse_int       14766131354   1.245    810    851   1.44  3>2       100     26       1.002
std_read_lines       2636801439   1.009    152    151   1.18  9>8       387     80       0.916
std_rng             15113981205   1.040    772    773   1.39  0>0        58     19       1.000
std_sort_stable      1614650566   1.594    101    131   1.47  1>1       228     87       1.000
std_sort_unstable    1306545244   1.323     73     80   1.35  1>1       132     71       0.998
std_spawn             658541725   1.002    817    808   1.40  0>0        60     22       0.999
std_str_ops          7518011937   1.150    349    380   1.42  2>1       190     52       1.007
std_term_feed       20392521820   1.233    690    799   1.26 10>7       272    184       1.000
std_utf8_validate    3062508125   1.183    173    217   1.32 10>7       258    176       0.996
std_width            6768097912   1.372    257    313   1.35 10>7       266    173       1.050
geomean insns 1.285  wall 1.141  n=43  vec loops 113->79  overflow checks left 5444 removed 2195
above +20%: 26 arena_trees collatz contracts contracts_plain fannkuch fmtints fmtloop heap interp iterchain iterloop json sort std_chars std_fmt_f64 std_fmt_int std_graphemes std_hash_churn std_hash_str std_hash_u64 std_parse_f64 std_parse_int std_sort_stable std_sort_unstable std_term_feed std_width
rust overflow-checks on/off: insns geomean 1.005 wall 0.942 n=20; max 1.076
vecloop/vec           2280922119   3.496    344    487   1.32  3>0
vecloop/raw           2595011066   3.068    352    496   1.30  2>0
```

The method is `/private/tmp/claude-501/-Users-magniff-workspace-vole/5ddff364-ae3e-4efe-9d23-745cc47fc2f3/scratchpad/numbers262/measure.sh`, `/private/tmp/claude-501/-Users-magniff-workspace-vole/5ddff364-ae3e-4efe-9d23-745cc47fc2f3/scratchpad/numbers262/rust.sh` and `/private/tmp/claude-501/-Users-magniff-workspace-vole/5ddff364-ae3e-4efe-9d23-745cc47fc2f3/scratchpad/numbers262/wrapsites.sh`,
described in commit 3e1d6322. The sites a program means to wrap, which
the Rust twins write as `wrapping_*`, were found by running the program:
each panic's site went on `$VOLE_PROTO_OVF_SKIP` until no panic was left.
That found 43 sites, 23 of them in std: the hash and PRNG mixes, and
parse's accumulators.

The wrap sites (program, exit status after skipping, its sites):

```
contracts 0 108:13,37:9,77:13,83:13,91:9
contracts_plain 0 93:13,23:9,62:13,68:13,76:9
heap 0 12:13,27:15,48:16
json 0 14:22
mandelbrot 0 35:24
purecall 0 38:13,31:9,29:9,47:13
purecall_hoisted 0 34:13,26:9,24:9,44:13
sort 0 28:13,44:15,60:16
wordcount 0 11:13,<std>:19226:5,24:13,75:29,75:17
std_fmt_f64 0 <std>:13235:14,25:13
std_fmt_f64_prec 0 23:13
std_fmt_int 0 16:13,<std>:629:9
std_graphemes 0 <std>:20958:5
std_hash_churn 0 <std>:19226:5
std_hash_str 0 <std>:19226:5
std_hash_u64 0 <std>:19226:5
std_parse_f64 0 <std>:13794:17,<std>:13068:6,<std>:13069:11,<std>:14021:20,41:21,<std>:14024:20
std_parse_int 0 <std>:13217:51,<std>:13068:6,<std>:13069:11,43:17
std_rng 0 <std>:17116:9,<std>:17117:9,<std>:17114:13,<std>:17161:19,11:15,<std>:17162:22,<std>:17203:18
std_sort_stable 0 24:15
std_sort_unstable 0 24:15
std_str_ops 0 <std>:13217:51
```

Where the cost is:

1. Reductions and index arithmetic in loops: `t += a[k] * b[k]`, std's
   `i + 1`, and `2 * i + 1` in the heap. Every one keeps its check, and
   the loop no longer vectorizes. iterloop and iterchain run at 3.7x and
   3.9x.
2. std's own loops (Vec, hashing, utf8, chars, fmt) carry checks that the
   ranges cannot discharge. A length is an i64 or u64 of unknown range,
   so `i <u len` says nothing about whether `i + 1` overflows in i64.
3. The checked operation is computed twice: `add` and then `cmn`, or
   `mul` + `mul` + `smulh`. MAdd fusion is lost too.

The prototype's known gaps, all of which make the numbers worse than the
final design would:

- Ovf is not fused with its own add, sub or mul (adds and b.vs);
- the range pass has no offsets (`i + k` with `i < n - k`) and no bound
  on lengths (an allocation's length is below 2^60, which would discharge
  `2*i+1` and every `i + 1` against a length);
- the vectorizer has no checked reduction (an overflow flag OR-ed across
  the lanes and tested at the loop's exit);
- the checks split blocks, which costs loop rotation (extra jumps).

## Step 3 (usize and isize)

Done in commit a2b2574d. The point of risk was code generation: ir_type
maps the two types to u64 and i64, and gen0 already decides by is_signed
and int_bits, so 36 explicit TY_U64/TY_I64 comparisons needed only three
fixes. The surprises were std's core budget (163840 bytes): the new impls
went into a lazy section of their own, with a `3usize` literal counted as
naming it. The `guide std` budget went to 22000 bytes. The hook's tools
binary still treats usize as u64, so until it is refreshed it reports 24
"conflicting impls" errors on the new std.

## What worked

- `volec query context` and `edit patch` on unfamiliar back-end code.
- Op::Bits as the model for a new pure op: fold, GVN, LICM and the
  emitter followed with few edits.
- Rosetta (`arch -x86_64`) runs `--target x86_64-macos` builds, so the
  x86-64 paths were tested after all.

## What cost time, ranked

1. Most bench programs wrap on purpose, which the first run showed: 22 of
   43 panicked. The skip list and its discovery loop were needed before
   any number meant anything.
2. In a match arm, `STATIC = v` reports "undefined variable
   'middle.lower.calls.STATIC'" (recorded with agent-feedback).
3. `ssa_write(cx, local, CUR, lower_operator(...))` reads CUR before the
   check moves it on, so the value had to be computed first.
4. tests/run.sh refuses to run until every VOLE_ name is in ENV_NAMES.

## Never used

`refactor signature` (default parameters kept the callers) and
`query impact`.

## Fix list, in order (tagged)

1. [design] Decision 6 needs the user: the default-on checks cost 1.29x
   here, against Rust's 1.005.
2. [optimizer] Before any re-measurement: fuse Ovf with its op, add
   offsets and length bounds to the ranges, and give the vectorizer a
   checked reduction.
3. [check] A clear error for assigning a non-Copy value to a static in a
   match arm.
