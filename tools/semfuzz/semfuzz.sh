#!/bin/sh
# (0.29) semfuzz.py, for tests/affected.sh (whose commands are sh scripts)
exec python3 "$(dirname "$0")/semfuzz.py" "$@"
