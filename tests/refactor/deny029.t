## 0.29: `volec check --deny=CODE` (tests/refactor/deny029/): a warning
## of that code or family is an error. `--deny=unsafe`: each unsafe site
## without both comments is reported where it is (no line that counts
## them past five), and so is each unsafe block with nothing unsafe
## inside (unsafe.unneeded, reported only when denied). Without the
## option the program checks, with its warning. The compiler's own source
## is checked so (tests/unsafe_audit.sh, tools/premerge.sh).
$ check main.vl
main.vl:4:1: warning[unsafe.unjustified] 7 unsafe sites lack `// UNSAFE:` and `// SAFETY:` comments (the first here) | help: each unsafe site says right above it why it cannot be safe and why it is sound; the try: line lists them | try: volec query unsafe --no-std --unjustified --root main.vl
ok: 0 errors, 1 warning in main.vl (1 file, 0 shaders)
$ check --deny=unsafe main.vl
main.vl:4:1: error[unsafe.unjustified] extern block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:9:13: error[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:10:13: error[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:11:13: error[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:12:13: error[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:14:13: error[unsafe.unjustified] unsafe block without a `// UNSAFE:` comment | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:19:13: error[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:19:13: error[unsafe.unneeded] unsafe block with nothing unsafe inside | help: take the word `unsafe` and its braces away, and the comments that justified it; the try: line does it for every such block | try: volec fix --only unneeded-unsafe main.vl
main.vl:22:13: error[unsafe.unneeded] unsafe block with nothing unsafe inside | help: take the word `unsafe` and its braces away, and the comments that justified it; the try: line does it for every such block | try: volec fix --only unneeded-justified main.vl
[exit 1]
$ check --deny=unsafe.unneeded main.vl
main.vl:4:1: warning[unsafe.unjustified] extern block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:9:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:10:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:11:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:12:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:14:13: warning[unsafe.unjustified] unsafe block without a `// UNSAFE:` comment | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:19:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:19:13: error[unsafe.unneeded] unsafe block with nothing unsafe inside | help: take the word `unsafe` and its braces away, and the comments that justified it; the try: line does it for every such block | try: volec fix --only unneeded-unsafe main.vl
main.vl:22:13: error[unsafe.unneeded] unsafe block with nothing unsafe inside | help: take the word `unsafe` and its braces away, and the comments that justified it; the try: line does it for every such block | try: volec fix --only unneeded-justified main.vl
[exit 1]
$ check --deny=use main.vl
main.vl:4:1: warning[unsafe.unjustified] 7 unsafe sites lack `// UNSAFE:` and `// SAFETY:` comments (the first here) | help: each unsafe site says right above it why it cannot be safe and why it is sound; the try: line lists them | try: volec query unsafe --no-std --unjustified --root main.vl
ok: 0 errors, 1 warning in main.vl (1 file, 0 shaders)
$ fix --only unneeded-justified main.vl
fixed 2 unneeded unsafe blocks	main.vl	+2 -4 lines
$ check --deny=unsafe.unneeded main.vl
main.vl:4:1: warning[unsafe.unjustified] extern block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:9:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:10:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:11:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:12:13: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:14:13: warning[unsafe.unjustified] unsafe block without a `// UNSAFE:` comment | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
ok: 0 errors, 6 warnings in main.vl (1 file, 0 shaders)
$ explain unsafe.unneeded
unsafe.unneeded: error (check --deny=unsafe)
(0.29) `volec check --deny=unsafe` (or `--deny=unsafe.unneeded`): an unsafe block of the program with nothing unsafe inside, `volec query unsafe`'s `none (unneeded)`: the checker read the block and found no operation that needs it (a raw pointer read, a C call, an `unsafe fn` called). It is reported only when denied: the check then runs as `query unsafe` does. The compiler's own source is held to none.
fix: `volec fix --only unneeded-unsafe` (the try: line) takes the block away and keeps its code; `--only unneeded-justified` one with `// UNSAFE:`/`// SAFETY:` comments, and the comments.
example:
    main.vl:9:5: error[unsafe.unneeded] unsafe block with nothing unsafe inside | help: take the word `unsafe` and its braces away, and the comments that justified it; the try: line does it for every such block | try: volec fix --only unneeded-unsafe main.vl
