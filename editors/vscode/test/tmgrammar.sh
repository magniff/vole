#!/bin/sh
# (0.26.0) tmgrammar.py, for tests/affected.sh (whose commands are sh scripts)
exec python3 "$(dirname "$0")/tmgrammar.py" "$@"
