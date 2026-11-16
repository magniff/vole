#!/bin/sh
# XFAIL: RT-130: volec assemble writes wrong bytes: a lock prefix drops its instruction, the largest branch displacements become 0, unpredictable ldp/stp are accepted (0.30.2)
# RT-130: each line is assembled alone by `volec assemble` and by cc; the
# two disassemblies must agree, and a line cc refuses must be refused.
# 0.30.1: `lock xaddq %rax, 8(%rdi)` (any lock with its instruction on
# one line) gives only f0; arm64 `b #134217724`, `bl #-134217728` and
# x86 `jmp .+2147483647`, `call .-2147483648` get displacement 0; arm64
# `ldp x0, x0, [x1]`, `ldp x0, x1, [x0], #16`, `stp x0, x1, [x0, #16]!`
# (unpredictable: cc refuses them) are accepted. Found by the review of
# g302std. Usage: rt_130_assemble_wrong_bytes.sh VOLEC (default volec).
V=${1:-volec}
case "$V" in */*) V=$(cd "$(dirname "$V")" && pwd)/$(basename "$V") ;; esac
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
bad=0
one() { # TARGET CC-TARGET LINE
    printf '\t.text\n\t.globl _f\n_f:\n\t%s\n\tret\n' "$3" > "$w/a.s"
    if ! cc -target "$2" -c "$w/a.s" -o "$w/c.o" 2>/dev/null; then
        if "$V" assemble --target "$1" "$w/a.s" -o "$w/v.o" >/dev/null 2>&1; then
            echo "accepted, cc refuses: $1: $3"; bad=1
        fi
        return
    fi
    if ! "$V" assemble --target "$1" "$w/a.s" -o "$w/v.o" >"$w/v.log" 2>&1; then
        echo "refused, cc assembles: $1: $3: $(head -1 "$w/v.log")"; bad=1; return
    fi
    c=$(objdump -d "$w/c.o" | grep -E '^ +[0-9a-f]+:' | sed 's/^ *[0-9a-f]*://')
    v=$(objdump -d "$w/v.o" | grep -E '^ +[0-9a-f]+:' | sed 's/^ *[0-9a-f]*://')
    [ "$c" = "$v" ] || { echo "differs: $1: $3"; echo "  cc:    $(echo $c)"; echo "  volec: $(echo $v)"; bad=1; }
}
X=x86_64-macos; XC=x86_64-apple-macos
A=aarch64-macos; AC=arm64-apple-macos
one $X $XC 'lock xaddq %rax, 8(%rdi)'
one $X $XC 'lock xaddl %eax, -2147483648(%rdi)'
one $X $XC 'lock cmpxchgq %rcx, 2147483647(%rsi,%rdx,8)'
one $X $XC 'jmp .+2147483647'
one $X $XC 'call .-2147483648'
one $A $AC 'b #134217724'
one $A $AC 'bl #-134217728'
one $A $AC 'ldp x0, x0, [x1]'
one $A $AC 'ldp x0, x1, [x0], #16'
one $A $AC 'stp x0, x1, [x0, #16]!'
exit $bad
