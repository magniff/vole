You are building a GPU demo program in **vole**, a young self-hosted systems language (its compiler is `volec`). You have never seen vole before: that is expected, and how you learn it is part of what is being measured. This is an evaluation of the language and its tools, so work the way you normally would, and report honestly at the end.

## Where and with what

- The repository is /Users/magniff/workspace/tachyon. Your project folder is `evals/tasks/0.25.2/NAME/` (NAME below). Create and change files ONLY inside your folder. Never edit the compiler (compiler/), std (compiler/std), tests/, docs/, other examples, or anything else; never commit or run git commands that change anything.
- The compiler is `/Users/magniff/workspace/tachyon/target/volec` (release 0.25.2; `volec --version`). Your program's root is `main.vl` in your folder, and it must build with exactly `volec main.vl -o NAME` run in your folder. No C helper files and no build scripts: std only.
- Read `/Users/magniff/workspace/tachyon/AGENTS.md` first and follow it: it explains the tools (`volec guide`, `volec query`, `volec edit`, `volec fix`, `volec check`, `volec test`, `volec probe`) and the hooks that run after your edits.
- Learn the language with `volec guide` (about 2k tokens, read it first), then `volec guide gpu`, `volec guide --list`, `volec guide --find WORDS`, `volec explain CODE` for any error code. The book is in /Users/magniff/workspace/tachyon/book/.
- Reference programs on the same std::gpu and std::window you will use (read them; don't copy them wholesale): `examples/gpu/fluid2d` (compute + window + headless, the closest model), `examples/gpu/life`, `examples/gpu/galaxy`, `examples/gpu/pathtrace`, `examples/gpu/voxel`. To read std's API: `volec query items std::gpu`, `volec query show std::gpu::Device`, `volec query context NAME`, and the same with `--root DIR` for an example's program.
- Shaders are WGSL, compiled by std::gpu::wgsl (to Metal on this Mac).

## What to build

A program with two modes:
1. **Windowed** (the default): the interactive demo in a window (std::window), as described in your task.
2. **Headless**: `./NAME --headless` runs without a display, prints the numbers that show it works (and `--shot FILE.ppm` writes a frame as a PPM image). You cannot see a window, so headless is how you check your own work. To look at an image, convert it and read the PNG: `python3 /Users/magniff/workspace/tachyon/evals/tasks/0.25.2/tools/ppm2png.py shot.ppm shot.png`, then read shot.png.
Also: `#[test]` tests for the CPU-side logic (`volec test main.vl`), and a `README.md` in your folder saying what it is, how to run it, the controls, and what you verified and how.

Aim for a demo that works and looks good, not a large one. If you get stuck on a compiler or std problem, find a workaround, and record the problem in one line with `/Users/magniff/workspace/tachyon/tools/agent-feedback "TOOL OR AREA" "WHAT WENT WRONG"`.

## Sharing the machine (read this)

Up to five agents build and run their demos on this machine at once, and there is one GPU. So:
- **Run every program that uses the GPU through the lock**: `/Users/magniff/workspace/tachyon/evals/tasks/0.25.2/tools/gpu-run [--timeout S] -- ./NAME --headless ...` (default timeout 300 s). It waits until no other agent's GPU program is running, runs yours alone and prints how long it waited and the load. Timings you report (frame times, tokens per second) must come from runs through gpu-run. Keep runs short (seconds, not minutes) so others don't wait long; `volec test` and builds don't need the lock.
- **Never open a window for long**: the screen belongs to a person. The windowed mode may be checked only with a short run that quits by itself (e.g. `--frames 120`), through gpu-run.
- Builds and checks may be slower than usual because others are compiling too. That is the harness, not vole: don't count it against the language or the tools, and don't spend your report on it. Mention contention only if it actually blocked you (one line, with the load gpu-run printed).

Rules from the project: no `unsafe` unless there is no safe way, and then with `// UNSAFE: why it cannot be safe` and `// SAFETY: why it is sound` comments right above it; no wildcard imports. Other agents are working in their own folders at the same time; the machine is shared.

## The report: ANALYSIS.md (required, last)

When the demo works, or you are truly stuck, write `ANALYSIS.md` in your folder. It is the most important output: it will be used to improve the language and the tools, so be **brutally honest**. Praise that isn't earned is useless; specific complaints are valuable. Sections:
1. **Result**: what works, what doesn't, what you verified and how (commands and output). Don't overstate it.
2. **How you worked**: the tools and commands you used, roughly how often, which ones helped, which didn't, and which you ignored and why (e.g. did you use `query`/`edit` or plain reading/writing? did the hooks help or get in the way?).
3. **What went well.**
4. **What went badly**: every error message that confused you (quote it), every place the guide or docs were missing or wrong, every time sink (how many attempts), every compiler, std or WGSL bug (with a minimal repro), every place where vole made something harder than Rust or C would have.
5. **The language**: what fought you (ownership, conventions, syntax, types, std's API), and what you liked.
6. **Suggestions**, ranked by how much time each would have saved you.
Include numbers where you can: builds, failed builds, turns spent on one problem.

## Harness notes (added 2026-10-28 18:35, after the first two agents finished)

- **ANALYSIS.md**: the harness may refuse to let you write a report file. If writing ANALYSIS.md is refused, don't fight it: put the whole analysis (all six sections) in your final message, and the orchestrator saves it as ANALYSIS.md verbatim.
- **Windowed runs**: one agent's `--frames 120` never returned under gpu-run while another's worked. Always give a windowed check `gpu-run --timeout 60`, and if it hangs, say so and move on; don't spend turns on it.
