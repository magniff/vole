# mandelbulb: eval record (vole 0.25.2.2, round 3)

One of ten GPU demos built by AI agents in the third round of the vole eval loop (round 1, on vole 0.25.2, is [../../0.25.2/mandelbulb/](../../0.25.2/mandelbulb/); round 2, on vole 0.25.2.1, is [../../0.25.2.1/mandelbulb/](../../0.25.2.1/mandelbulb/)) (see [../SUMMARY.md](../SUMMARY.md)).

| | |
|---|---|
| model | Claude Haiku 5.5 (`claude-haiku-5-5`) |
| reasoning effort | medium |
| agent | Claude Code subagent, type `general-purpose`, run in the background by the orchestrator (Claude Opus 5.5) |
| harness | Claude Code with the repository's hooks (check after every edit, applying only the mechanical fixes and listing the rest as suggested; query-first; turn-end) |
| compiler | vole 0.25.2.2 (`target/volec`, tag `v0.25.2.2`, commit bf92f5fa) |
| started | 2026-10-29 03:03 CET |
| duration | 7.6 min (455 s) |
| tokens | 170,392 (as reported by the harness) |
| tool calls | 56 |
| shared machine | up to 5 agents at once; GPU programs run through [`../tools/gpu-run`](../tools/gpu-run) (one at a time) |

## Files

- [ANALYSIS.md](ANALYSIS.md): the agent's own report (tools used, what went well and badly, suggestions), asked to be brutally honest. Where the harness refused the agent's write, the orchestrator saved it verbatim from the agent's final message (the file says so).
- [REVIEW.md](REVIEW.md): the review of its code and claims.
- [PROGRAM.md](PROGRAM.md): the agent's README for its program (how to build and run it, controls, what it verified).
- The program: `main.vl` and its modules; build with `volec main.vl -o mandelbulb`.

## The prompt

The agent got this prompt, verbatim, and read the shared brief [../BRIEF.md](../BRIEF.md) as it says. The brief is round 2's with the paths and version changed; every agent saw the same brief.

```
You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `mandelbulb`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/mandelbulb/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `mandelbulb`.

Your task:

A Mandelbulb (and a second fractal, e.g. a Julia set in quaternions or a Mandelbox) raymarched in a fragment or compute shader: distance estimation, soft shadows, ambient occlusion, a smooth fly-through camera with mouse and keys, a power parameter you can change live. Headless renders fixed views to PPM and prints timing.
```

## Tool use, from the transcript

Counted from the agent's transcript (tool calls deduplicated; `volec` subcommands parsed from every shell command; "hook blocks" are commands refused by tools/agent-hooks):

| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |
|---|---|---|---|---|---|---|---|---|
| mandelbulb | 55 | 35 | 4 | 5 | 11 | guide 8, build 7, query show 5, query items 4, fmt 4, test 2 | 0 () | 1 |
