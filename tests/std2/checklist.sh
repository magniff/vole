#!/bin/sh
# (0.27.2) compiler/std2/checklist.tsv is what the tree makes: the
# checklist tool's --check, for tests/affected.map's `cmd std2chk` (which
# runs a shell script). Arguments go to the tool (--volec PATH).
exec python3 "$(dirname "$0")/../../tools/std2-checklist.py" "$@" --check
