#!/bin/sh
# Two compilers on one input: the instructions of each phase and optimizer
# pass by both, and the difference (0.30). usage and what it prints:
# tools/perf-diff.sh --help (tools/perf-diff.py, which this runs).
exec python3 "$(dirname "$0")/perf-diff.py" "$@"
