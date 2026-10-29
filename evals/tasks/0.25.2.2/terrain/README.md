# terrain: eval record (vole 0.25.2.2, round 3)

One of ten GPU demos built by AI agents in the third round of the vole eval loop (round 1, on vole 0.25.2, is [../../0.25.2/terrain/](../../0.25.2/terrain/); round 2, on vole 0.25.2.1, is [../../0.25.2.1/terrain/](../../0.25.2.1/terrain/)) (see [../SUMMARY.md](../SUMMARY.md)).

| | |
|---|---|
| model | Claude Haiku 5.5 (`claude-haiku-5-5`) |
| reasoning effort | medium |
| agent | Claude Code subagent, type `general-purpose`, run in the background by the orchestrator (Claude Opus 5.5) |
| harness | Claude Code with the repository's hooks (check after every edit, applying only the mechanical fixes and listing the rest as suggested; query-first; turn-end) |
| compiler | vole 0.25.2.2 (`target/volec`, tag `v0.25.2.2`, commit bf92f5fa) |
| started | 2026-10-29 03:12 CET |
| duration | 14.5 min (871 s) |
| tokens | 187,317 (as reported by the harness) |
| tool calls | 48 |
| shared machine | up to 5 agents at once; GPU programs run through [`../tools/gpu-run`](../tools/gpu-run) (one at a time) |

## Files

- [ANALYSIS.md](ANALYSIS.md): the agent's own report (tools used, what went well and badly, suggestions), asked to be brutally honest. Where the harness refused the agent's write, the orchestrator saved it verbatim from the agent's final message (the file says so).
- [REVIEW.md](REVIEW.md): the review of its code and claims.
- [PROGRAM.md](PROGRAM.md): the agent's README for its program (how to build and run it, controls, what it verified).
- The program: `main.vl` and its modules; build with `volec main.vl -o terrain`.

## The prompt

The agent got this prompt, verbatim, and read the shared brief [../BRIEF.md](../BRIEF.md) as it says. The brief is round 2's with the paths and version changed; every agent saw the same brief.

```
You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `terrain`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/terrain/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `terrain`.

Your task:

A procedural terrain fly-over: a heightmap from fractal noise generated on the GPU, a mesh with distance-based level of detail, a sun with a shadow map (a depth-only pass), fog and simple materials by height and slope (grass, rock, snow), water at sea level. Headless writes shots from fixed cameras and prints checks (e.g. the noise's range, triangle counts per LOD).
```

## Tool use, from the transcript

Counted from the agent's transcript (tool calls deduplicated; `volec` subcommands parsed from every shell command; "hook blocks" are commands refused by tools/agent-hooks):

| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |
|---|---|---|---|---|---|---|---|---|
| terrain | 47 | 36 | 0 | 7 | 4 | guide 6, query show 5, build 4, check 3, query items 2, test 2 | 2 (query-first 2) | 4 |
