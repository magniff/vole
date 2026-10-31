# gen0: -O0, and the driver of every level

`gen/mod.vl`'s `compile_program` drives code generation at every level:
at -O1 and -O2 it lowers, optimizes and emits through `middle` and
`back`; at -O0 it runs the 0.1 code generator, which walks the checked
AST and writes assembly through the target interface. -O0 shares only
the front end with the other levels, so it is the oracle they are tested
against.

(0.26.1) The -O0 generator reads each function's places IR instead
(0.26.2: only) (`gen/places.vl`, the same bodies as
`middle/lower/places.vl` takes at -O1 and -O2, the drop shims with
them): a frame slot per local (a statement temporary's shared with the
later ones, one read by the next statement left in the accumulator),
the blocks in reverse postorder, calls, intrinsics and vectors through
the AST walk's functions with their operands bound (`gen_expr` of a
bound node is its IR operand). What stays of the AST walk: those
functions, a literal's or a name's value (`gen_expr`), and an atomic
intrinsic's body (0.26.2's step 8b deleted the rest).

| module | |
|---|---|
| `gen/` | the driver, and -O0's generator: functions (`mod`), the places IR's statements and terminators (`places`, 0.26.1), literals, names, operators and casts (`expr`), calls (`call`), vectors (`vector`) |
| `target.vl` | the target interface: the machine model's virtual registers, output helpers, data, run-time checks, dispatch to the instruction set |
| `arm64.vl` | AArch64 for -O0 (Apple's arm64 ABI, AAPCS64; Mach-O, ELF) |
| `x86_64.vl` | x86-64 for -O0 (System V; AT&T syntax) |
