#!/bin/sh
# tests/fuzz/pm_model.py, the model of the moves' plan, run as the map's
# and the gate's commands are (sh FILE ARGS): usage as the model's.
exec python3 -I "$(dirname "$0")/pm_model.py" "$@"
