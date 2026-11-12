## The edition's flag and variable (0.28.0; tests/refactor/envedition/):
## there is one edition. `--edition rust` and VOLE_EDITION=rust are
## accepted and change nothing: the program is read as it is without
## them.
% volec check main.vl
main.vl:15:10: error[type error] expected '&mut i64', got '&i64' | help: the types differ in mutability (rustc E0308): the parameter takes an exclusive reference, `&mut x` | try: &mut x | try: volec fix --suggested main.vl
main.vl:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
[exit 1]
% VOLE_EDITION=rust volec check main.vl
main.vl:15:10: error[type error] expected '&mut i64', got '&i64' | help: the types differ in mutability (rustc E0308): the parameter takes an exclusive reference, `&mut x` | try: &mut x | try: volec fix --suggested main.vl
main.vl:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
[exit 1]
% volec --edition rust check main.vl
main.vl:15:10: error[type error] expected '&mut i64', got '&i64' | help: the types differ in mutability (rustc E0308): the parameter takes an exclusive reference, `&mut x` | try: &mut x | try: volec fix --suggested main.vl
main.vl:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
[exit 1]
## The old edition is refused, by the flag and by the variable, whatever
## the command; nothing is read or written.
% volec --edition mvs check main.vl
error: the MVS edition is gone (0.28.0): there is one edition, Rust's surface (volec guide rust)
[exit 1]
% VOLE_EDITION=mvs volec check main.vl
error: the MVS edition is gone (0.28.0): there is one edition, Rust's surface (volec guide rust)
[exit 1]
% VOLE_EDITION=mvs volec fix --suggested main.vl
error: the MVS edition is gone (0.28.0): there is one edition, Rust's surface (volec guide rust)
[exit 1]
% volec --edition mvs main.vl -o prog
error: the MVS edition is gone (0.28.0): there is one edition, Rust's surface (volec guide rust)
[exit 1]
## Any other name is no edition.
% volec --edition 2015 check main.vl
error: unknown edition (expected --edition rust)
[exit 1]
% git status --short
