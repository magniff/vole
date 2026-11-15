## 0.30.1, RT-CG-7: --verify-regalloc follows the code of every parallel
## move as it is emitted (back/regalloc/movecode.vl): each destination
## must end with its source's value, no other register or frame byte may
## be written, and every instruction must be one of the moves' forms. The
## program is genmoves.awk's seed 74 in a frame past 16 KB (pad=2100),
## where 0.30.0 saved an integer in x17 and overwrote it with an f32
## slot's address (tests/run's rt_cg_007_seed74_*). It builds clean:
% awk -v seed=74 -v pad=2100 -f $T/../fuzz/genmoves.awk > m.vl
% VOLE_CACHE=off volec m.vl -O2 --target aarch64-macos --verify-regalloc -o m.o
ok: wrote m.o
% VOLE_CACHE=off volec m.vl -O2 --target x86_64-macos --verify-regalloc -o m.o
ok: wrote m.o
## VOLE_PLANT_RT_CG_7 (tests only, under --verify-regalloc) plants a
## fault in the moves' steps, one for each rule; each is reported. x17:
## RT-CG-7 itself (an f32 slot past 16 KB addressed through x17, which
## ma_scratch no longer refuses), at -O2 and -O1:
% VOLE_PLANT_RT_CG_7=x17 VOLE_CACHE=off volec m.vl -O2 --target aarch64-macos --verify-regalloc -o m.o
internal error: register allocation of main: the code of a parallel move leaves a destination without its source's value: `move -2117 -> -2126, byte 0`
[exit 1]
% VOLE_PLANT_RT_CG_7=x17 VOLE_CACHE=off volec m.vl -O1 --target aarch64-macos --verify-regalloc -o m.o
internal error: register allocation of main: the code of a parallel move leaves a destination without its source's value: `move -2126 -> -2116, byte 0`
[exit 1]
## scratch: the same address, but ma_scratch still guarding x17 while
## the steps run: refused before any code is made
% VOLE_PLANT_RT_CG_7=scratch VOLE_CACHE=off volec m.vl -O2 --target aarch64-macos --verify-regalloc -o m.o
error: internal error: x17 taken as a scratch register while it holds a value (a parallel move's save or a copy's piece)
[exit 1]
## temp: a move between slots through an allocated register
% VOLE_PLANT_RT_CG_7=temp VOLE_CACHE=off volec m.vl -O2 --target aarch64-macos --verify-regalloc -o m.o
internal error: register allocation of main: the code of a parallel move writes a register no move writes: `register 28`
[exit 1]
% VOLE_PLANT_RT_CG_7=temp VOLE_CACHE=off volec m.vl -O2 --target x86_64-macos --verify-regalloc -o m.o
internal error: register allocation of main: the code of a parallel move writes a register no move writes: `register 1`
[exit 1]
## insn: a nop after each step
% VOLE_PLANT_RT_CG_7=insn VOLE_CACHE=off volec m.vl -O2 --target aarch64-macos --verify-regalloc -o m.o
internal error: register allocation of main: the code of a parallel move has an instruction the check does not follow: `    nop`
[exit 1]
% VOLE_PLANT_RT_CG_7=insn VOLE_CACHE=off volec m.vl -O2 --target x86_64-macos --verify-regalloc -o m.o
internal error: register allocation of main: the code of a parallel move has an instruction the check does not follow: `    nop`
[exit 1]
## frame: each store to a slot made to the save area too
% VOLE_PLANT_RT_CG_7=frame VOLE_CACHE=off volec m.vl -O2 --target aarch64-macos --verify-regalloc -o m.o
internal error: register allocation of main: the code of a parallel move writes a byte of the frame no move writes: `sp + 17040`
[exit 1]
% VOLE_PLANT_RT_CG_7=frame VOLE_CACHE=off volec m.vl -O2 --target x86_64-macos --verify-regalloc -o m.o
internal error: register allocation of main: the code of a parallel move writes a byte of the frame no move writes: `sp + 17136`
[exit 1]
## Without --verify-regalloc the switch is not read:
% VOLE_PLANT_RT_CG_7=x17 VOLE_CACHE=off volec m.vl -O2 --target aarch64-macos -o m.o
ok: wrote m.o
## and a value it does not name is an error, not a pass:
% VOLE_PLANT_RT_CG_7=x18 VOLE_CACHE=off volec m.vl -O2 --target aarch64-macos --verify-regalloc -o m.o
error: VOLE_PLANT_RT_CG_7 is x17, temp, insn, frame or scratch
[exit 1]
## (0.30.1) x86-64 reaches the frame with 32-bit displacements: a frame
## past 2 GB is an error (0.30.0's assembler kept the displacements' low
## 32 bits, `subq $3000001744, %rsp` was `subq $-1294965552`); AArch64
## builds it, through movz/movk and a register
% printf 'fn main() {\n    let mut a = [0u8; 3000000000usize];\n    a[2999999999] = 7;\n    println("{}", a[2999999999]);\n}\n' > big.vl
% VOLE_CACHE=off volec big.vl -O2 --target x86_64-macos -o big.o
error: a stack frame past 2 GB: x86-64 reaches its frame with 32-bit displacements (put the large value on the heap)
[exit 1]
% VOLE_CACHE=off volec big.vl -O2 --target aarch64-macos -o big.o
ok: wrote big.o
## at -O0 too (its own frame; the assembler refuses the subq)
% VOLE_CACHE=off volec big.vl -O0 --target x86_64-macos -o big.o
internal error: cannot assemble: an immediate a 64-bit operation cannot sign-extend from 32 bits: subq $6000000656, %rsp
[exit 1]
