# windtunnel: eval record (vole 0.25.2.2, round 3)

One of ten GPU demos built by AI agents in the third round of the vole eval loop (round 1, on vole 0.25.2, is [../../0.25.2/windtunnel/](../../0.25.2/windtunnel/); round 2, on vole 0.25.2.1, is [../../0.25.2.1/windtunnel/](../../0.25.2.1/windtunnel/)) (see [../SUMMARY.md](../SUMMARY.md)).

| | |
|---|---|
| model | Claude Haiku 5.5 (`claude-haiku-5-5`) |
| reasoning effort | medium |
| agent | Claude Code subagent, type `general-purpose`, run in the background by the orchestrator (Claude Opus 5.5) |
| harness | Claude Code with the repository's hooks (check after every edit, applying only the mechanical fixes and listing the rest as suggested; query-first; turn-end) |
| compiler | vole 0.25.2.2 (`target/volec`, tag `v0.25.2.2`, commit bf92f5fa) |
| started | 2026-10-29 03:21 CET |
| duration | 13.4 min (807 s) |
| tokens | 213,056 (as reported by the harness) |
| tool calls | 63 |
| shared machine | up to 5 agents at once; GPU programs run through [`../tools/gpu-run`](../tools/gpu-run) (one at a time) |

## Files

- [ANALYSIS.md](ANALYSIS.md): the agent's own report (tools used, what went well and badly, suggestions), asked to be brutally honest. Where the harness refused the agent's write, the orchestrator saved it verbatim from the agent's final message (the file says so).
- [REVIEW.md](REVIEW.md): the review of its code and claims.
- [PROGRAM.md](PROGRAM.md): the agent's README for its program (how to build and run it, controls, what it verified).
- The program: `main.vl` and its modules; build with `volec main.vl -o windtunnel`.

## The prompt

The agent got this prompt, verbatim, and read the shared brief [../BRIEF.md](../BRIEF.md) as it says. The brief is round 2's with the paths and version changed; every agent saw the same brief.

```
You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `windtunnel`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/windtunnel/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `windtunnel`.

Your task:

A 2D Lattice-Boltzmann wind tunnel (D2Q9, BGK collision) on the GPU: flow from the left around obstacles you draw and erase with the mouse, showing speed, vorticity or dye (keys switch views), a Reynolds-number control, stable at the default settings. Headless prints checks (mass conservation over steps, a known result such as vortex shedding behind a cylinder at a suitable Reynolds number) and writes shots.
```

## Tool use, from the transcript

Counted from the agent's transcript (tool calls deduplicated; `volec` subcommands parsed from every shell command; "hook blocks" are commands refused by tools/agent-hooks):

| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |
|---|---|---|---|---|---|---|---|---|
| windtunnel | 62 | 42 | 9 | 5 | 6 | build 8, query show 6, guide 4, fmt 3, query items 2, check 2, fix 1, test 1 | 0 () | 1 |
