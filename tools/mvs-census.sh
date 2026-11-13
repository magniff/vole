#!/bin/sh
# (0.28.0) mvs-census.py, for tests/affected.sh (whose commands are sh scripts)
exec python3 "$(dirname "$0")/mvs-census.py" "$@"
