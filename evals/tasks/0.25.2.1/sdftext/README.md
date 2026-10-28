# sdftext: eval record (vole 0.25.2.1, round 2)

One of ten GPU demos built by AI agents in the second round of the vole eval loop (round 1, on vole 0.25.2, is [../../0.25.2/sdftext/](../../0.25.2/sdftext/)) (see [../SUMMARY.md](../SUMMARY.md)).

| | |
|---|---|
| model | Claude Haiku 5.5 (`claude-haiku-5-5`) |
| reasoning effort | medium |
| agent | Claude Code subagent, type `general-purpose`, run in the background by the orchestrator (Claude Opus 5.5) |
| harness | Claude Code with the repository's hooks (check after every edit with automatic `fix --suggested`, query-first, turn-end) |
| compiler | vole 0.25.2.1 (`target/volec`, tag `v0.25.2.1`, commit 28e78c2a) |
| started | 2026-10-28 22:44 CET |
| duration | 11.0 min (662 s) |
| tokens | 226,893 (as reported by the harness) |
| tool calls | 52 |
| shared machine | up to 5 agents at once; GPU programs run through [`../tools/gpu-run`](../tools/gpu-run) (one at a time) |

## Files

- [ANALYSIS.md](ANALYSIS.md): the agent's own report (tools used, what went well and badly, suggestions), asked to be brutally honest. Where the harness refused the agent's write, the orchestrator saved it verbatim from the agent's final message (the file says so).
- [REVIEW.md](REVIEW.md): the review of its code and claims.
- [PROGRAM.md](PROGRAM.md): the agent's README for its program (how to build and run it, controls, what it verified).
- The program: `main.vl` and its modules; build with `volec main.vl -o sdftext`.

## The prompt

The agent got this prompt, verbatim, and read the shared brief [../BRIEF.md](../BRIEF.md) as it says. The brief is round 1's with the paths changed and round 1's harness notes folded in; every agent saw the same brief.

```
You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `sdftext`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/sdftext/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `sdftext`.

Your task:

Signed-distance-field text and a small immediate-mode UI on the GPU. Build an SDF glyph atlas at startup (from a vector font description you write for a subset of glyphs, or by computing distance fields from a bitmap font you rasterise yourself), render crisp text at any scale and rotation from it, and build a few widgets (buttons, a slider, a text field, a scrolling list) that react to the mouse and keyboard. Headless renders a page of text at several sizes to PPM and checks the atlas.
```

## Tool use, from the transcript

Counted from the agent's transcript (tool calls deduplicated; `volec` subcommands parsed from every shell command; "hook blocks" are commands refused by tools/agent-hooks):

| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |
|---|---|---|---|---|---|---|---|---|
| sdftext | 51 | 33 | 5 | 9 | 4 | query show 14, query items 8, build 7, guide 6, check 3, test 3, query context 1 | 0 () | 1 |
