## (0.29) `~x` is not an operator (syntax.tilde): an integer's complement
## is `!x`. Each `~` is an error with its exact fix, and `fix --suggested`
## writes `!` at every one in one checked edit (`~~x` too: two errors,
## two fixes). A `!` of an integer is the complement inside the compiler,
## and no tool writes it back as `~`: an inlined body, a rewrite's holes
## and fmt keep `!`; a rewrite that would write `~` is refused by its
## check, and writes nothing.
$ check
main.vl:1:19: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl
main.vl:4:5: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl
main.vl:9:17: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl
main.vl:15:42: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl
main.vl:15:43: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl
[exit 1]
$ explain syntax.tilde
syntax.tilde: error
(0.29) `~x`, the complement of an integer in C and in vole until 0.28. `~` is not an operator: `!x` is the bitwise not of an integer and the logical not of a bool, as in Rust (0.27.2 on read both spellings). The expression is read as `!x`, so its operand is checked too.
fix: Write `!x` (the error's fix: `volec fix --suggested FILE` rewrites every `~` of the program that is an operator).
example:
    fn main() {
        let mask: u32 = ~0xffu32;
    }
    
    main.vl:2:21: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x`
      help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust)
      try: volec fix --suggested main.vl
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -1 +1 @@
-const KEEP: u32 = ~0xffu32;
+const KEEP: u32 = !0xffu32;
@@ -4 +4 @@
-    ~(1u32 << bit)
+    !(1u32 << bit)
@@ -9 +9 @@
-    flags & m & ~KEEP
+    flags & m & !KEEP
@@ -15 +15 @@
-    println("{} {} {}", clear(flags, 3), ~~flags, odd);
+    println("{} {} {}", clear(flags, 3), !!flags, odd);
$ fix --suggested
fixed 5 suggested fixes	main.vl	+4 -4 lines
$ check
ok: 0 errors in main.vl
$ refactor inline mask
inlined crate::mask at 1 call, deleted it	main.vl	+1 -5 lines
$ rewrite '$a & !$b' --list
main.vl:5:5	$a=flags & m	$b=KEEP
$ rewrite '!$x' '~$x'
main.vl:1:19: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl  [edited: crate::KEEP]
main.vl:4:13: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl  [edited: crate::clear]
main.vl:5:17: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl  [edited: crate::clear]
main.vl:10:15: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl  [edited: crate::main]
main.vl:11:42: error[syntax.tilde] `~` is not an operator; an integer's complement is `!x` | help: write `!x`: bitwise not on an integer, logical not on a bool (as in Rust) | try: volec fix --suggested main.vl  [edited: crate::main]
note rewrite.nested: 1 site inside a rewritten one is left; run the rewrite again
error edit.breaks: 5 new errors; nothing written; the first: main.vl:1:19: `~` is not an operator; an integer's complement is `!x`
note rewrite.where: $x has 2 types at the sites: u32 (5 sites), bool (1 site); --where takes the ones the replacement fits
try: volec rewrite '!$x' '~$x' --where '$x: u32'
try: volec rewrite '!$x' '~$x' --where '$x: bool'
try: volec rewrite '!$x' '~$x' --no-check
[exit 1]
$ fmt main.vl
note fmt.none: 1 file formatted already
% cat main.vl
const KEEP: u32 = !0xffu32;

fn clear(flags: u32, bit: u32) -> u32 {
    let m = !(1u32 << bit);
    flags & m & !KEEP
}

fn main() {
    let flags: u32 = 0x1ff;
    let odd = !(flags % 2 == 0);
    println("{} {} {}", clear(flags, 3), !!flags, odd);
}
% volec main.vl -o prog >/dev/null && ./prog
247 511 true
ok: built prog
