## 0.25.3: `volec check`'s unsafe.unjustified (tests/refactor/unsafe0253/):
## a warning for each unsafe site (a block, an `unsafe fn`, an extern
## block) without `// UNSAFE:` and `// SAFETY:` right above it, its try:
## line the file's sites (`volec query unsafe`).
$ check
main.vl:16:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:20:13: warning[unsafe.unjustified] unsafe block without a `// UNSAFE:` comment | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
ok: 0 errors, 2 warnings in main.vl
## --deny-warnings: errors.
$ check --deny-warnings
main.vl:16:5: error[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
main.vl:20:13: error[unsafe.unjustified] unsafe block without a `// UNSAFE:` comment | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
[exit 1]
## Past five, one warning counts them (a program of legacy unsafe).
$ check many/main.vl
many/main.vl:2:1: warning[unsafe.unjustified] 6 unsafe sites lack `// UNSAFE:` and `// SAFETY:` comments (the first here) | help: each unsafe site says right above it why it cannot be safe and why it is sound; the try: line lists them | try: volec query unsafe --no-std --unjustified --root many/main.vl
ok: 0 errors, 1 warning in many/main.vl
$ check many/main.vl --deny-warnings
many/main.vl:2:1: error[unsafe.unjustified] 6 unsafe sites lack `// UNSAFE:` and `// SAFETY:` comments (the first here) | help: each unsafe site says right above it why it cannot be safe and why it is sound; the try: line lists them | try: volec query unsafe --no-std --unjustified --root many/main.vl
[exit 1]
$ explain unsafe.unjustified
unsafe.unjustified: warning (check)
(0.25.3) `volec check`: an unsafe site of the program (an `unsafe { }` block, an `unsafe fn`, an `extern` block) without both justification comments right above it: `// UNSAFE:` (why it cannot be safe) and `// SAFETY:` (why it is sound). Right above: the comment lines directly over the statement or item the site starts (no blank line between), comments inside that statement before the site, or one ending its line. The first five are reported one by one, then one warning counts the rest; an error with --deny-warnings. std's sites are not the program's: `volec query unsafe std` lists them.
fix: Try the safe way first (std's APIs, Vec, slices, a borrow); `volec query unsafe FILE` (the try: line) says what each site does (its operations and class: an unsafe block with nothing unsafe inside is `none (unneeded)`, remove it). Where unsafe stays, write the two comments above it.
example:
    main.vl:9:5: warning[unsafe.unjustified] unsafe block without `// UNSAFE:` and `// SAFETY:` comments | help: say right above it why it cannot be safe (`// UNSAFE: ...`) and why it is sound (`// SAFETY: ...`); the try: line lists the file's sites and what each does | try: volec query unsafe main.vl
