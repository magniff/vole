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
EOF
echo "enc: $refused registers of the wrong class or number refused"
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
[ $status = 0 ] && echo "enc: ok"
exit $status
