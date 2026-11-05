#!/bin/sh
# The try: lines of the borrow checker's diagnostics, run (0.27.1,
# docs/design/borrowck.md §14.1: each code's try: has a case here). Each
# tests/borrowck-try/NAME/main.vl is a rust-edition program with
# `// CODE: borrowck.X` (the first error `check --values=error` reports)
# and `// TRY: text` lines; the runner is tests/own-try/run.sh's, which
# says what it checks.
#
# usage: tests/borrowck-try/run.sh [-c COMPILER] [FILTER]
HERE=$(cd "$(dirname "$0")" && pwd)
exec sh "$HERE/../own-try/run.sh" -d "$HERE" "$@"
