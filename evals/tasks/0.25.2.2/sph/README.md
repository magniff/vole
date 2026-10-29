# sph: eval record (vole 0.25.2.2, round 3)

One of ten GPU demos built by AI agents in the third round of the vole eval loop (round 1, on vole 0.25.2, is [../../0.25.2/sph/](../../0.25.2/sph/); round 2, on vole 0.25.2.1, is [../../0.25.2.1/sph/](../../0.25.2.1/sph/)) (see [../SUMMARY.md](../SUMMARY.md)).

| | |
|---|---|
| model | Claude Haiku 5.5 (`claude-haiku-5-5`) |
| reasoning effort | medium |
| agent | Claude Code subagent, type `general-purpose`, run in the background by the orchestrator (Claude Opus 5.5) |
| harness | Claude Code with the repository's hooks (check after every edit, applying only the mechanical fixes and listing the rest as suggested; query-first; turn-end) |
| compiler | vole 0.25.2.2 (`target/volec`, tag `v0.25.2.2`, commit bf92f5fa) |
| started | 2026-10-29 02:55 CET |
| duration | 28.8 min (1726 s) |
| tokens | 377,666 (as reported by the harness) |
| tool calls | 223 |
| shared machine | up to 5 agents at once; GPU programs run through [`../tools/gpu-run`](../tools/gpu-run) (one at a time) |

## Files

- [ANALYSIS.md](ANALYSIS.md): the agent's own report (tools used, what went well and badly, suggestions), asked to be brutally honest. Where the harness refused the agent's write, the orchestrator saved it verbatim from the agent's final message (the file says so).
- [REVIEW.md](REVIEW.md): the review of its code and claims.
- [PROGRAM.md](PROGRAM.md): the agent's README for its program (how to build and run it, controls, what it verified).
- The program: `main.vl` and its modules; build with `volec main.vl -o sph`.

## The prompt

The agent got this prompt, verbatim, and read the shared brief [../BRIEF.md](../BRIEF.md) as it says. The brief is round 2's with the paths and version changed; every agent saw the same brief.

```
You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `sph`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/sph/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `sph`.

Your task:

A 2D SPH fluid of at least 100,000 particles in a box you can tilt or stir with the mouse. The neighbour search runs on the GPU (a grid: counting sort or radix sort by cell, a prefix sum), then density, pressure and viscosity forces, then integration; draw particles coloured by speed. Headless prints checks (the sort and the prefix sum against the CPU, the mean density settling, no particle escaping) and writes a shot.
```

## Tool use, from the transcript

Counted from the agent's transcript (tool calls deduplicated; `volec` subcommands parsed from every shell command; "hook blocks" are commands refused by tools/agent-hooks):

| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |
|---|---|---|---|---|---|---|---|---|
| sph | 222 | 107 | 2 | 6 | 2 | build 20, guide 5, check 5, query show 4, test 3, query items 2 | 1 (query-first 1) | 10 |
