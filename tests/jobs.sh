# The transcript runners' jobs (0.30): sourced by tests/query/run.sh and
# tests/refactor/run.sh (`. tests/jobs.sh`), which run their transcripts
# and checks as jobs: selected by name, some at once, each one's result
# printed as it ends. POSIX sh and awk only.
#
# The runner sets WORK (its scratch directory) and defines
#   run_job KIND NAME K   one job, its report on stdout (`pass NAME ...`,
#                         `FAIL NAME ...` and why, `xfail NAME ...`); K is
#                         the job's number, for a directory of its own
# and lists its jobs as lines `KIND NAME`.

# The lines of stdin (`KIND NAME`) whose NAME the filters in $1 select
# (one per line: a FILTER selects the names containing it, =NAME only
# NAME; none: every line).
jobs_select() {
    if [ -z "$1" ]; then
        cat
        return
    fi
    JOBS_FILTERS=$1 awk 'BEGIN {
            nf = split(ENVIRON["JOBS_FILTERS"], f, "\n")
            for (i = 1; i <= nf; i++)
                if (f[i] ~ /^=/) exact[substr(f[i], 2)] = 1
                else if (f[i] != "") part[++np] = f[i]
        }
        $2 in exact { print; next }
        { for (i = 1; i <= np; i++) if (index($2, part[i])) { print; next } }'
}

# The filters of $1 as a message names them: `a, =b`.
jobs_filters_text() {
    printf '%s' "$1" | awk 'NF { printf "%s%s", sep, $0; sep = ", " }'
}

# Runs the jobs of file $1, $2 at once: each job's report is printed
# whole when the job ends, in the order they end (with one at once: the
# file's order), and kept in $WORK/res/K. A job that reports no verdict
# (it died) is a FAIL of its name.
jobs_run() {
    mkdir -p "$WORK/res"
    rm -f "$WORK/jobslots"
    mkfifo "$WORK/jobslots"
    exec 4<>"$WORK/jobslots"
    jr_i=0
    while [ "$jr_i" -lt "$2" ]; do
        echo >&4
        jr_i=$((jr_i + 1))
    done
    {
        jr_k=0
        while read -r jr_kind jr_name; do
            jr_k=$((jr_k + 1))
            read -r _ <&4
            # (the job gives its slot back however it ends, as tests/run.sh's)
            (
                trap 'echo >&4' EXIT
                trap 'exit 1' HUP INT TERM
                run_job "$jr_kind" "$jr_name" "$jr_k" >"$WORK/res/$jr_k" 2>&1 </dev/null
                grep -q -E '^(pass|FAIL|xfail|skip) ' "$WORK/res/$jr_k" \
                    || echo "FAIL $jr_name: the job reported nothing" >>"$WORK/res/$jr_k"
                echo "$jr_k"
            ) &
        done <"$1"
        wait
    } | while read -r jr_done; do
        cat "$WORK/res/$jr_done"
    done
    exec 4>&-
}

# After jobs_run: how many reports of kind $1 (pass, FAIL, xfail) there are.
jobs_count() {
    cat "$WORK"/res/* 2>/dev/null | grep -c "^$1 "
}
