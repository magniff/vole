# Eval round 3: vole 0.25.2.2, the same ten GPU demos

**Date:** 2026-10-29, 02:55–03:28 CET.

**The setup:**
- **Same as rounds 1 and 2** ([../0.25.2/SUMMARY.md](../0.25.2/SUMMARY.md), [../0.25.2.1/SUMMARY.md](../0.25.2.1/SUMMARY.md)): the same ten tasks and prompts, and the same brief with only the paths and version changed.
- **Agents:** Claude Haiku 5.5 at medium effort, at most five at a time.
- **GPU:** one shared GPU behind [tools/gpu-run](tools/gpu-run).
- **Compiler:** vole 0.25.2.2, the release built from round 2's feedback ([its notes](https://github.com/magniff/vole/releases/tag/v0.25.2.2)).
- **Records:** each folder has the agent's [ANALYSIS.md](qwen35/ANALYSIS.md), a [REVIEW.md](qwen35/REVIEW.md) and a [README.md](qwen35/README.md) with the prompt, parameters and tool counts.
- **Reviews:** two Opus reviewers, working to [REVIEW-RUBRIC.md](REVIEW-RUBRIC.md). It is round 2's rubric with two questions replaced: did the program use 0.25.2.2's new features, and does it depend on the mapped-view bug below. They rebuilt every program and re-ran every check. The orchestrator re-ran qwen35's check itself: `fails 0`, the same numbers as the agent's.
- **This is the last round of the loop.** The next release, 0.25.3, goes back to the roadmap and takes this round's findings with it.

## Results

| project | time | tokens | tool calls | result | code | honesty | round 2 (time, calls, grades) |
|---|---|---|---|---|---|---|---|
| [qwen35](qwen35/) | 28.6 min | 371k | 131 | A | B+ | A- | 24.1 min, 113, A/B+/A- |
| [ocean](ocean/) | 13.7 min | 230k | 50 | A | A- | A | 11.8 min, 59, A-/B+/A |
| [sph](sph/) | 28.8 min | 378k | 223 | B+ | B+ | B | 9.7 min, 39, A-/A-/A- |
| [physarum](physarum/) | 6.4 min | 152k | 26 | A- | A- | A- | 7.6 min, 51, A/B+/A- |
| [cloth](cloth/) | 19.0 min | 289k | 82 | B+ | B | A- | 12.3 min, 56, A-/B+/B+ |
| [mandelbulb](mandelbulb/) | 7.6 min | 170k | 56 | A- | B+ | A | 5.9 min, 32, A-/B+/A |
| [deferred](deferred/) | 14.0 min | 202k | 47 | B+ | A- | B+ | 12.6 min, 50, A/A-/A |
| [terrain](terrain/) | 14.5 min | 187k | 48 | B+ | A- | A- | 12.5 min, 63, B+/B+/A- |
| [sdftext](sdftext/) | 13.8 min | 212k | 61 | A- | B+ | A | 11.0 min, 52, A/A-/A |
| [windtunnel](windtunnel/) | 13.4 min | 213k | 63 | B+ | B+ | B- | 13.8 min, 81, A-/B+/A- |

Time, tokens and tool calls are as the harness reports them. qwen35's time includes about 4 minutes after its report, while its own sampling run waited for the GPU. [TOOL-STATS.md](TOOL-STATS.md) has the per-tool counts from the transcripts.

**Against rounds 1 and 2:**

| measure | round 1 (0.25.2) | round 2 (0.25.2.1) | round 3 (0.25.2.2) |
|---|---|---|---|
| agent time, all ten | 165 min | 121 min | 160 min |
| the same, without sph | | 111 min | 131 min |
| tokens | 2.33 M | 2.23 M | 2.40 M |
| tool calls (transcripts) | 849 | 586 | 776 |
| the same, without sph | | 547 | 554 |
| hook blocks | 53 | 5 | 7 |
| failed tool calls | 79 | 29 | 34 |
| turns lost to a uniform never written | at least 1 agent (physarum) | 2 agents (sph about 3, windtunnel about 10) | none |
| turns lost to a `?`-argument soundness bug | 1 agent (cloth found `f(make()?)?`) | 2 agents (ocean about 4 cycles, terrain about 15) | none |
| wrong automatic fixes | in 4 of 10 runs | none | none |
| windowed `--frames N` runs that returned | 5 of 10 | 10 of 10 | 10 of 10 |
| results graded A or A- | 3 | 9 | 5 |

**Reading the numbers:**
- **Round 3 cost more than round 2.** Almost all of the difference is sph: 223 tool calls against 39, spent by its own account on SPH physics (the pressure stiffness, a kernel Laplacian that is negative at short range, the viscosity stability bound), not on vole. Without sph, tool calls are flat: 554 against 547.
- **Run-to-run noise is now larger than the effect of a release's fixes.** Each task ran once per round, so one agent's physics detour moves the totals more than ten diagnostics do. That is why the loop stops here.
- **The grades come from different reviewers** in each round, so read them as rough. This round's reviewers re-derived several headline numbers and lowered grades where a check passed for the wrong reason (windtunnel, deferred, cloth).
- **What 0.25.2.2 measurably removed:** no agent lost a turn to a uniform read before it was written, or to the `?`-argument soundness bug, against four agents and about 30 turns in round 2.

**Things only 0.25.2.2 made possible:**
- **One WGSL module serving several pipelines**, now that a pipeline's layout is the bindings its own entry points use:
  - terrain: shadow, terrain and sea from one module;
  - ocean: sky and water;
  - physarum: init and clear.
- No program needed the new storage formats; one hand-rolled clamp per program shows the integer methods went unfound (below).

## What the agents said

**Still liked:**
- the check hook after every edit and its mechanical fixes (`&x` for an inout argument, `var` for `let mut`, Rust's spellings), all correct again;
- `volec test` comparing -O0 with -O2;
- std::gpu's `requires` messages, which name the binding, the usage flag or the limit and how to fix it;
- `query show` and `query items` for std's signatures.

**Complaints, by how many agents raised them:**
- **Which GPU handles move and which copy** (six agents: qwen35, deferred, terrain, windtunnel, sdftext, cloth). `Device`, `Buffer` and `BindGroup` are move-only. A struct literal, a `Vec::push`, a tuple `let` or an `if` that picks one of two fields moves them. qwen35 needed four attempts. The guide has no one-line rule, and `own.moved` does not point to one.
- **GPU timestamps** (four agents): frame times are wall clock through `wait_idle`, and other agents' load makes them swing tenfold.
- **The check hook's rewrites** (five agents): "changed on disk since you last read it" does not say what changed. qwen35's later Python string replacement silently missed after the hook had rewritten the same line.
- **A window not on the display** (all ten could not test keys, mouse or frame time): frames come from the 10 Hz timer. Several printed a frame time anyway, which reads like a measurement. They want an offscreen event loop for testing.
- **Float literals are f64** (four agents): arrays of literals and `let dt = 1.0 / 60.0` need annotations, and the error comes at the use, not at the `let`.
- **The query tools are still unused:** `query context`, `edit` and `refactor` were never used, for all practical purposes. ocean said it thought they were "for compiler sources".

## Bugs found

- **Soundness, std::gpu.** A `map_read` view can change under the program.
  - **The pattern:** `let v = gpu::f32s(r.map_read(dev))`, then a copy into `r`, submitted while `v` lives. The checker accepts it, because both are read-only borrows of `r`.
  - **Why std misses it:** `map_read` never marks the buffer mapped, so std's `gpu.state` checks never fire.
  - **The effect:** the orchestrator's repro prints `before 1, after 2`. Without the wait, the CPU read races the GPU write.
  - **The bind-group route:** std also allows MAP_READ with STORAGE, which WebGPU forbids.
  - **How it was found:** ocean asked whether a mapped view stays valid while the GPU writes the buffer, and its own code keeps one alive across 60 such submits without reading it again. No program's results depend on it.
  - **Status:** being fixed first in 0.25.3, with wgpu's model: the buffer is mapped until `unmap(dev)`, and a submit that writes a mapped buffer stops.
- **std::cli:** `m.get("flag").is_some()` on a flag compiles and is always false. `m.flag` is right. terrain opened a window instead of running headless and lost a 120-second GPU run.
- **Misleading messages:**
  - `fn f(inout x: T)` says `'inout' is a keyword ... rename it` instead of "the mode goes after the colon, `x: inout T`" (sdftext).
  - `unknown type 'Matches'` suggests `use std::string::Matches` (it is `std::cli::Matches`) (mandelbulb).
  - `volec build main.vl -o x` says only `cannot read build` (cloth).
  - `unknown module 'gpu'` after `use std::gpu::{Surface}` does not say `use std::gpu;` (physarum).
  - `const X: str = "..."` is refused with a message that lists string literals as allowed (qwen35).
- **Tools:** `volec test` cannot show a test's printed output; sdftext forced asserts to fail to see values. `query show` on a struct does not list its methods.
- **Our own harness:** `gpu-run` waited on a killed program without a timeout, so a program stuck in the driver would have held the GPU lock for everyone. sph found this; it was fixed during the round.

## What the reviews add

- **sph's windowed picture was not a bug.**
  - **What the agent saw:** the agent reported its 2560×1440 window shot as off-centre and squashed.
  - **The cause:** the window steps 20 substeps a frame, so its 120 frames show 0.12 s of fluid against the headless shot's 0.3 s. The reviewer reproduced the same picture headless.
  - **Grades:** the agent's report also misstated its default run length, and its honesty grade fell for both.
- **Checks that pass for the wrong reasons:**
  - **windtunnel:**
    - its Strouhal number, 0.168 against a published 0.165, is averaged over four periods of a still-growing transient. At saturation it is about 0.178.
    - its mass drift of 2.2e-5 is the f32 sum of its 7-digit weights, not round-off noise.
  - **deferred:** at 4,096 lights, 66% of the lit tiles hit a silent 127-light cap, so the timing at that count measures truncated work.
  - **physarum:** the trail-total check cannot see the agents' behaviour, because every agent deposits the same amount.
  - **terrain:** the LOD check is close to a tautology.
  - **mandelbulb:** the headless check only rejects a flat picture.
- **The window's size goes stale in four programs** (sph, physarum, cloth, windtunnel): each captured the window size once, so the mouse mapping is wrong after a resize. fluid2d, the example they copied, maps with the surface's current size, so this is a guide gap, not the example's bug.
- **std goes unfound:** hand-written `PI` (four programs), integer and float `clamp`, and `x - x != 0.0` or `h != h` for NaN, where std has `f64::consts::PI`, `clamp` on every number and `is_finite`/`is_nan`.
- **cloth runs 841 compute passes a frame**, because it could not find whether dispatches in one pass are ordered. They are, but the guide says so only under "atomics".

## Into 0.25.3

- the mapped-view soundness fix (started);
- std::cli refuses `get` on a flag;
- the five messages above;
- `volec test` showing printed output;
- `query show` listing a type's methods;
- the guide:
  - which handles move and how to keep them in structs and `Vec`s;
  - dispatch ordering in its own section;
  - the mouse mapped with the surface's current size;
  - a ping-pong section;
  - string constant forms;
- the hook naming what it rewrote;
- a way to find "is there a std function for X";
- GPU timestamps, if they fit;
- the roadmap's own 0.25.3 items: multi-line strings and file embedding, TTY output, and the rest in docs/roadmap.md.
