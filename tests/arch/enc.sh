#!/bin/sh
# The x86-64 encoder against the system assembler, byte for byte (0.19,
# docs/design/arch.md §6.8): tests/arch/enc_x86.s holds every instruction
# of compiler/arch/insn_x86.def, and the AVX moves the back end writes,
# with low and high registers (VEX.R, X, B and vvvv), both vector widths
# (VEX.L), every class's operand order and memory operands with each
# addressing form (written by tools/arch/x86_families.py --write). It is
# assembled by the compiler (`volec assemble`) and by cc, for
# x86_64-macos (Mach-O) and x86_64-linux (ELF), and the two disassemblies
# must be the same. Nothing is run: x86-64 is not executed in 0.19. Every
# mnemonic of insn_x86.def must appear in the corpus (else the corpus is
# stale: rerun the script). Skipped when cc cannot assemble for x86-64.
#
# usage: tests/arch/enc.sh [-c COMPILER] [-o DIR]
set -u
LC_ALL=C
export LC_ALL
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER="$ROOT/target/volec"
OUT="$ROOT/target/arch-enc"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        -o) OUT=$2; shift 2 ;;
        *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac
mkdir -p "$OUT"
CORPUS="$ROOT/tests/arch/enc_x86.s"
status=0

# The corpus covers the table.
missing=$(grep -v '^[[:space:]]*#' "$ROOT/compiler/arch/insn_x86.def" | grep -v '^[[:space:]]*$' \
    | sed 's/ |.*//' | while read -r mn; do
        grep -q "^    $mn " "$CORPUS" || echo "$mn"
    done)
if [ -n "$missing" ]; then
    echo "enc: not in tests/arch/enc_x86.s (run tools/arch/x86_families.py --write):" $missing
    status=1
fi

for t in x86_64-macos x86_64-linux; do
    case $t in
        x86_64-macos) ct=x86_64-apple-macos ;;
        *) ct=x86_64-linux-gnu ;;
    esac
    if ! cc -target "$ct" -c "$CORPUS" -o "$OUT/$t.cc.o" 2>"$OUT/$t.cc.log"; then
        echo "enc: skipped $t: cc does not assemble for it ($(head -1 "$OUT/$t.cc.log"))"
        continue
    fi
    if ! "$COMPILER" assemble --target "$t" "$CORPUS" -o "$OUT/$t.o" >"$OUT/$t.log" 2>&1; then
        echo "enc: FAIL $t: $(head -3 "$OUT/$t.log")"
        status=1
        continue
    fi
    objdump -d --no-leading-addr "$OUT/$t.o" | sed -n -e '/^</p' -e '/^ /p' >"$OUT/$t.ours"
    objdump -d --no-leading-addr "$OUT/$t.cc.o" | sed -n -e '/^</p' -e '/^ /p' >"$OUT/$t.theirs"
    n=$(grep -c '^ ' "$OUT/$t.theirs")
    if [ "$n" -lt 1000 ] || ! cmp -s "$OUT/$t.ours" "$OUT/$t.theirs"; then
        echo "enc: FAIL $t: the encodings differ from cc's (< ours, > cc's):"
        diff "$OUT/$t.ours" "$OUT/$t.theirs" | head -20
        status=1
        continue
    fi
    echo "enc: $t: $n instructions, the same bytes as cc's"
done

# (0.30.1, RT-CG-5) A register of the wrong class or of a number its
# class has not is refused, never encoded as another register: arm64's
# `str x63` was `str xzr` (a field masked to 5 bits), `str d-15` was
# `str s0`; x86-64's `movsd m, %r10` was xmm10, `movq %xmm15, m` a 4-byte
# movd. Each line alone in a function must fail with "cannot assemble";
# needs no cc.
refused=0
while IFS='|' read -r t line; do
    [ -z "$t" ] && continue
    printf '.text\n.globl _f\n_f:\n    %s\n    ret\n' "$line" >"$OUT/refuse.s"
    if "$COMPILER" assemble --target "$t" "$OUT/refuse.s" -o "$OUT/refuse.o" >"$OUT/refuse.log" 2>&1; then
        echo "enc: FAIL $t: encoded, not refused: $line"
        status=1
    elif ! grep -q 'cannot assemble' "$OUT/refuse.log"; then
        echo "enc: FAIL $t: not refused by the assembler: $line ($(head -1 "$OUT/refuse.log"))"
        status=1
    else
        refused=$((refused + 1))
    fi
done <<'EOF'
aarch64-macos|str x63, [sp, #16]
aarch64-macos|ldr x32, [sp]
aarch64-macos|ldr d32, [sp]
aarch64-macos|str q40, [sp]
aarch64-macos|mov x31, x0
aarch64-macos|mov w31, w0
aarch64-macos|fmov d5, x63
aarch64-macos|fadd v32.2d, v0.2d, v1.2d
aarch64-macos|str d-15, [sp, #16]
aarch64-macos|ldr x-1, [sp]
aarch64-macos|str sp, [x0]
aarch64-macos|add x0, xzr, #1
aarch64-macos|adds sp, x0, #1
aarch64-macos|orr sp, x0, x1
aarch64-macos|ldr x0, [xzr]
aarch64-macos|ldr x0, [w1]
aarch64-macos|ldr v1, [sp]
x86_64-macos|movsd 16(%rsp), %r10
x86_64-macos|movss %eax, 16(%rsp)
x86_64-macos|movapd %rax, %xmm1
x86_64-macos|addsd %rax, %xmm0
x86_64-macos|movl %xmm15, 16(%rsp)
x86_64-macos|movw %xmm1, (%rax)
x86_64-macos|movd %xmm1, %xmm0
x86_64-macos|addq %xmm1, %rax
x86_64-macos|leaq (%rax), %xmm0
x86_64-macos|cvtsi2sdq %xmm2, %xmm1
x86_64-macos|cvttsd2si %xmm1, %xmm2
x86_64-macos|movq %xmm16, 16(%rsp)
x86_64-macos|call *%xmm0
x86_64-macos|jmp *%xmm1
x86_64-macos|xaddq %xmm0, (%rax)
x86_64-macos|cmpxchgl %eax, %ecx
x86_64-macos|pmovmskb %rax, %eax
x86_64-macos|pextrq $1, %rax, %rcx
x86_64-macos|pinsrq $1, %xmm1, %xmm2
x86_64-macos|popcntq %xmm1, %rax
x86_64-macos|paddsb %rax, %xmm1
x86_64-macos|vpmovmskb %xmm1, %xmm2
x86_64-macos|andnq %xmm1, %rax, %rcx
x86_64-macos|leaq 3000000032(%rsp), %rdi
x86_64-macos|subq $3000001744, %rsp
x86_64-macos|movl %eax, -2147483649(%rbp)
x86_64-macos|addq $4294967295, %rax
x86_64-macos|andq $-2147483649, %rcx
x86_64-macos|testq $2147483648, %rax
x86_64-macos|testq $2147483648, %rcx
x86_64-macos|movq $2147483648, %rax
x86_64-macos|movq $2147483648, 8(%rsp)
x86_64-macos|movl $4294967296, %eax
x86_64-macos|movw $65536, %ax
x86_64-macos|movb $256, %al
aarch64-macos|movz x0, #70000
aarch64-macos|movk x0, #1, lsl #8
aarch64-macos|movz w0, #1, lsl #32
aarch64-macos|ldp x0, x1, [sp, #1024]
aarch64-macos|stp x0, x1, [sp, #-1024]!
aarch64-macos|ldp x0, x1, [sp], #1024
aarch64-macos|ldp x0, x1, [sp, #4]
aarch64-macos|ldp q0, q1, [sp, #1024]
EOF
echo "enc: $refused registers of the wrong class or number, and immediates and offsets their fields cannot hold, refused"
# (0.30.1, RT-CG-7) The fields at their limits, as cc writes them:
# x86-64's displacements and a 64-bit operation's immediate are signed 32
# bits (0.30.0 wrote a frame past 2 GB's `subq $3000001744, %rsp` and
# `leaq 3000000032(%rsp)` with their low 32 bits), a 32-bit operation's
# immediate any 32 bits; AArch64's pairs reach -64 to 63 units, movz and
# movk 16 bits at a shift of 0 to 48 (0.30.0 kept the low bits of both).
printf '.text\n.globl _f\n_f:\n    leaq 2147483647(%%rsp), %%rdi\n    leaq -2147483648(%%rsp), %%rdi\n    subq $-2147483648, %%rsp\n    addq $2147483647, %%rax\n    andq $2147483647, %%rcx\n    testq $-1, %%rax\n    movq $-2147483648, %%rax\n    movq $2147483647, 8(%%rsp)\n    movl $4294967295, %%eax\n    movl $3000000000, %%r9d\n    movw $65535, %%ax\n    movb $255, %%al\n    movl %%eax, -2147483648(%%rbp)\n    ret\n' >"$OUT/x86lim.s"
if cc -target x86_64-apple-macos -c "$OUT/x86lim.s" -o "$OUT/x86lim.cc.o" 2>/dev/null; then
    if ! "$COMPILER" assemble --target x86_64-macos "$OUT/x86lim.s" -o "$OUT/x86lim.o" >"$OUT/x86lim.log" 2>&1; then
        echo "enc: FAIL x86lim: $(head -1 "$OUT/x86lim.log")"
        status=1
    else
        objdump -d --no-leading-addr "$OUT/x86lim.o" | sed -n '/^ /p' >"$OUT/x86lim.ours"
        objdump -d --no-leading-addr "$OUT/x86lim.cc.o" | sed -n '/^ /p' >"$OUT/x86lim.theirs"
        if ! cmp -s "$OUT/x86lim.ours" "$OUT/x86lim.theirs"; then
            echo "enc: FAIL x86lim: the encodings differ from cc's (< ours, > cc's):"
            diff "$OUT/x86lim.ours" "$OUT/x86lim.theirs" | head -10
            status=1
        else
            echo "enc: x86-64 displacements and immediates at their limits: the same bytes as cc's"
        fi
    fi
fi
printf '.text\n.globl _f\n_f:\n    ldp x0, x1, [sp, #504]\n    stp x0, x1, [sp, #-512]!\n    ldp x0, x1, [sp], #504\n    ldp q0, q1, [sp, #1008]\n    ldp d0, d1, [sp, #-512]\n    movz x0, #65535, lsl #48\n    movk w0, #65535, lsl #16\n    ret\n' >"$OUT/a64lim.s"
if cc -target arm64-apple-macos -c "$OUT/a64lim.s" -o "$OUT/a64lim.cc.o" 2>/dev/null; then
    if ! "$COMPILER" assemble --target aarch64-macos "$OUT/a64lim.s" -o "$OUT/a64lim.o" >"$OUT/a64lim.log" 2>&1; then
        echo "enc: FAIL a64lim: $(head -1 "$OUT/a64lim.log")"
        status=1
    else
        objdump -d --no-leading-addr "$OUT/a64lim.o" | sed -n '/^ /p' >"$OUT/a64lim.ours"
        objdump -d --no-leading-addr "$OUT/a64lim.cc.o" | sed -n '/^ /p' >"$OUT/a64lim.theirs"
        if ! cmp -s "$OUT/a64lim.ours" "$OUT/a64lim.theirs"; then
            echo "enc: FAIL a64lim: the encodings differ from cc's (< ours, > cc's):"
            diff "$OUT/a64lim.ours" "$OUT/a64lim.theirs" | head -10
            status=1
        else
            echo "enc: AArch64 pairs and movz/movk at their limits: the same bytes as cc's"
        fi
    fi
fi
# The moves of an xmm register to and from memory, as cc writes them.
printf '.text\n.globl _f\n_f:\n    movq %%xmm15, 16(%%rsp)\n    movq 16(%%rsp), %%xmm15\n    movq %%xmm0, (%%rax)\n    movq (%%r12,%%rax,8), %%xmm9\n    movq %%xmm3, %%rax\n    movq %%rbx, %%xmm2\n    movd %%xmm3, 8(%%rsp)\n    movd 8(%%rsp), %%xmm3\n    ret\n' >"$OUT/movq.s"
if cc -target x86_64-apple-macos -c "$OUT/movq.s" -o "$OUT/movq.cc.o" 2>/dev/null; then
    if ! "$COMPILER" assemble --target x86_64-macos "$OUT/movq.s" -o "$OUT/movq.o" >"$OUT/movq.log" 2>&1; then
        echo "enc: FAIL movq: $(head -1 "$OUT/movq.log")"
        status=1
    else
        objdump -d --no-leading-addr "$OUT/movq.o" | sed -n '/^ /p' >"$OUT/movq.ours"
        objdump -d --no-leading-addr "$OUT/movq.cc.o" | sed -n '/^ /p' >"$OUT/movq.theirs"
        if ! cmp -s "$OUT/movq.ours" "$OUT/movq.theirs"; then
            echo "enc: FAIL movq: the encodings differ from cc's (< ours, > cc's):"
            diff "$OUT/movq.ours" "$OUT/movq.theirs" | head -10
            status=1
        else
            echo "enc: movq and movd to and from memory: the same bytes as cc's"
        fi
    fi
fi
# (0.30.1) AArch64's sp and xzr each where its field means it, and the
# loads and stores of q, h and b registers (h and b were encoded as q),
# as cc writes them.
printf '.text\n.globl _f\n_f:\n    mov x0, xzr\n    add sp, sp, #16\n    sub sp, sp, #32\n    mov x29, sp\n    mov sp, x29\n    add x0, sp, x1\n    cmp sp, #0\n    str xzr, [sp]\n    subs x0, sp, #1\n    add x0, x1, xzr\n    ldr q1, [sp, #16]\n    str q1, [sp, #16]\n    ldr h1, [sp, #2]\n    str h1, [sp, #2]\n    ldr b1, [sp, #1]\n    str b1, [sp, #1]\n    ldr h2, [x0, x1, lsl #1]\n    ldr b2, [x0, x1]\n    ret\n' >"$OUT/a64regs.s"
if cc -target arm64-apple-macos -c "$OUT/a64regs.s" -o "$OUT/a64regs.cc.o" 2>/dev/null; then
    if ! "$COMPILER" assemble --target aarch64-macos "$OUT/a64regs.s" -o "$OUT/a64regs.o" >"$OUT/a64regs.log" 2>&1; then
        echo "enc: FAIL a64regs: $(head -1 "$OUT/a64regs.log")"
        status=1
    else
        objdump -d --no-leading-addr "$OUT/a64regs.o" | sed -n '/^ /p' >"$OUT/a64regs.ours"
        objdump -d --no-leading-addr "$OUT/a64regs.cc.o" | sed -n '/^ /p' >"$OUT/a64regs.theirs"
        if ! cmp -s "$OUT/a64regs.ours" "$OUT/a64regs.theirs"; then
            echo "enc: FAIL a64regs: the encodings differ from cc's (< ours, > cc's):"
            diff "$OUT/a64regs.ours" "$OUT/a64regs.theirs" | head -10
            status=1
        else
            echo "enc: AArch64 sp, xzr, q, h and b: the same bytes as cc's"
        fi
    fi
fi
# (0.30.1) A symbol is never a register: where the instruction takes a
# symbol (a branch's target, adrp's page, a relocation) `d5`, `w7`, `x3`,
# `q1` and `sp` are labels, as C's names may be (0.30.0 refused them or
# took them for registers). cc's assembler refuses these names, so the
# check is the branches' targets and the relocations' symbols; ELF, where
# a C name is not prefixed with `_`.
printf '.text\n.globl f\nf:\n    bl d5\n    bl w7\n    b x3\n    cbz x0, q1\n    tbz x0, #3, sp\n    adrp x1, ext_d6\n    bl ext_d6\n    adrp x2, w8\n    add x2, x2, :lo12:w8\n    bl w8\n    ret\nd5:\n    ret\nw7:\n    ret\nx3:\n    ret\nq1:\n    ret\nsp:\n    ret\n' | sed 's/ext_d6/d6/g' >"$OUT/sym.s"
if ! "$COMPILER" assemble --target aarch64-linux "$OUT/sym.s" -o "$OUT/sym.o" >"$OUT/sym.log" 2>&1; then
    echo "enc: FAIL symbols named like registers: $(head -1 "$OUT/sym.log")"
    status=1
else
    got=$({ objdump -d --no-leading-addr "$OUT/sym.o" | sed -n '/^ /p' | grep -oE '<(d5|w7|x3|q1|sp)>'
        objdump -r "$OUT/sym.o" | grep -oE 'R_AARCH64_[A-Z0-9_]+[[:space:]]+(d6|w8)'; } | tr -s ' \t' ' ' | tr '\n' ',')
    want='<d5>,<w7>,<x3>,<q1>,<sp>,R_AARCH64_ADR_PREL_PG_HI21 d6,R_AARCH64_CALL26 d6,R_AARCH64_ADR_PREL_PG_HI21 w8,R_AARCH64_ADD_ABS_LO12_NC w8,R_AARCH64_CALL26 w8,'
    if [ "$got" != "$want" ]; then
        echo "enc: FAIL symbols named like registers: $got, not $want"
        status=1
    else
        echo "enc: AArch64 symbols named like registers: labels and relocations"
    fi
fi
[ $status = 0 ] && echo "enc: ok"
exit $status
