"""Write evals/tasks/0.25.2.1/NAME/README.md (the eval record) for each project;
the agent's own README.md is kept as PROGRAM.md (moved, unchanged)."""
import os, re, subprocess
E = "/Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1"
B = "/Users/magniff/workspace/tachyon/.claude/briefs/eval-02521"
runs = {}
usage = {}
for line in open(f"{B}/runs.tsv"):
    f = line.rstrip("\n").split("\t")
    if len(f) >= 6 and f[1].startswith("a") and f[2].startswith("haiku"):
        runs[f[0]] = dict(agent=f[1], model=f[2], effort=f[3], type=f[4], started=f[5])
    elif f[0] in ("finished", "usage") and len(f) >= 4:
        name = f[1]
        for x in f[2:]:
            m = re.match(r"(\d+) tokens", x)
            if m: usage.setdefault(name, {})["tokens"] = int(m.group(1))
            m = re.match(r"(\d+) tool uses", x)
            if m: usage.setdefault(name, {})["tools"] = int(m.group(1))
            m = re.match(r"(\d+) s$", x)
            if m: usage.setdefault(name, {})["secs"] = int(m.group(1))
stats = {}
for line in open(f"{B}/tool-stats.md"):
    f = [c.strip() for c in line.strip().strip("|").split("|")]
    if f and f[0] in runs:
        stats[f[0]] = f
hdr = "| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |\n|---|---|---|---|---|---|---|---|---|"
commit = subprocess.run(["git", "-C", "/Users/magniff/workspace/tachyon", "rev-parse", "--short", "v0.25.2.1^{commit}"], capture_output=True, text=True).stdout.strip()
for name, r in sorted(runs.items()):
    d = f"{E}/{name}"
    if os.path.exists(f"{d}/README.md") and not os.path.exists(f"{d}/PROGRAM.md"):
        os.rename(f"{d}/README.md", f"{d}/PROGRAM.md")
    prompt = open(f"{B}/prompts/{name}.md").read().rstrip()
    u = usage.get(name, {})
    mins = f"{u['secs']/60:.1f} min ({u['secs']} s)" if "secs" in u else "?"
    s = stats.get(name)
    srow = ("| " + " | ".join(s) + " |") if s else "(no stats)"
    out = f"""# {name}: eval record (vole 0.25.2.1, round 2)

One of ten GPU demos built by AI agents in the second round of the vole eval loop (round 1, on vole 0.25.2, is [../../0.25.2/{name}/](../../0.25.2/{name}/)) (see [../SUMMARY.md](../SUMMARY.md)).

| | |
|---|---|
| model | Claude Haiku 5.5 (`claude-haiku-5-5`) |
| reasoning effort | medium |
| agent | Claude Code subagent, type `general-purpose`, run in the background by the orchestrator (Claude Opus 5.5) |
| harness | Claude Code with the repository's hooks (check after every edit with automatic `fix --suggested`, query-first, turn-end) |
| compiler | vole 0.25.2.1 (`target/volec`, tag `v0.25.2.1`, commit {commit}) |
| started | {r['started']} |
| duration | {mins} |
| tokens | {u.get('tokens', '?'):,} (as reported by the harness) |
| tool calls | {u.get('tools', '?')} |
| shared machine | up to 5 agents at once; GPU programs run through [`../tools/gpu-run`](../tools/gpu-run) (one at a time) |

## Files

- [ANALYSIS.md](ANALYSIS.md): the agent's own report (tools used, what went well and badly, suggestions), asked to be brutally honest. Where the harness refused the agent's write, the orchestrator saved it verbatim from the agent's final message (the file says so).
- [REVIEW.md](REVIEW.md): the review of its code and claims.
- [PROGRAM.md](PROGRAM.md): the agent's README for its program (how to build and run it, controls, what it verified).
- The program: `main.vl` and its modules; build with `volec main.vl -o {name}`.

## The prompt

The agent got this prompt, verbatim, and read the shared brief [../BRIEF.md](../BRIEF.md) as it says. The brief is round 1's with the paths changed and round 1's harness notes folded in; every agent saw the same brief.

```
{prompt}
```

## Tool use, from the transcript

Counted from the agent's transcript (tool calls deduplicated; `volec` subcommands parsed from every shell command; "hook blocks" are commands refused by tools/agent-hooks):

{hdr}
{srow}
"""
    open(f"{d}/README.md", "w").write(out)
    print("wrote", d + "/README.md")
