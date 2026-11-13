## The edition's option is gone (0.29.0; tests/refactor/editiongone/):
## there is one language. `--edition`, with any value, in either form
## and before or after the command, is an unknown option whose message
## says so; nothing is read or written.
% volec --edition rust check main.vl
error: unknown option '--edition': there is one language (0.28.0) and no edition to choose; leave the option out
[exit 1]
% volec check main.vl --edition=rust
error: unknown option '--edition': there is one language (0.28.0) and no edition to choose; leave the option out
[exit 1]
% volec --edition mvs main.vl -o prog
error: unknown option '--edition': there is one language (0.28.0) and no edition to choose; leave the option out
[exit 1]
% volec fix --edition rust main.vl
error: unknown option '--edition': there is one language (0.28.0) and no edition to choose; leave the option out
[exit 1]
## VOLE_EDITION is a variable like any other the compiler does not read.
% VOLE_EDITION=mvs volec check main.vl
main.vl:15:10: error[type error] expected '&mut i64', got '&i64' | help: the types differ in mutability (rustc E0308): the parameter takes an exclusive reference, `&mut x` | try: &mut x | try: volec fix --suggested main.vl
main.vl:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
[exit 1]
## After `--` the word is the program's own argument.
% volec run -- --edition rust
main.vl:15:10: error[type error] expected '&mut i64', got '&i64' | help: the types differ in mutability (rustc E0308): the parameter takes an exclusive reference, `&mut x` | try: &mut x | try: volec fix --suggested main.vl
main.vl:17:13: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
[exit 1]
% git status --short
