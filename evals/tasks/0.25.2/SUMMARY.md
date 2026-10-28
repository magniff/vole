# Eval round 1: vole 0.25.2, ten GPU demos by Haiku agents

**Date:** 2026-10-28, 18:09–19:35 CET.

**The setup:**
- **Agents:** ten Claude Haiku 5.5 agents at medium reasoning effort, one per task, at most five at a time.
- **Briefing:** each agent got the same brief ([BRIEF.md](BRIEF.md)) and one task paragraph.
- **Programs:** each wrote its demo from scratch in vole 0.25.2, on std::gpu and std::window, std only.
- **Harness:** Claude Code with the repository's hooks.
- **Shared machine:** GPU runs went through [tools/gpu-run](tools/gpu-run), so only one ran at a time.
- **Records:** each folder has the agent's own brutally honest [ANALYSIS.md](qwen35/ANALYSIS.md), a [REVIEW.md](qwen35/REVIEW.md) and a [README.md](qwen35/README.md) with the prompt, parameters and tool counts.
- **Reviews:** two Opus reviewer agents wrote them against [REVIEW-RUBRIC.md](REVIEW-RUBRIC.md). They rebuilt every program, re-ran every check and read all the code. The orchestrator re-ran the key claims itself.

This round is the baseline. Its feedback becomes vole 0.25.2.1, and then the same ten tasks run again.

## Results

| project | time | tokens | tool calls | result | code | honesty | in one line |
|---|---|---|---|---|---|---|---|
| [qwen35](qwen35/) | 38.8 min | 395k | 180 | A | B | A- | Qwen3.5-0.8B on the GPU from vole: exact token ids, greedy 24/24 on 3 prompts, top-10 logits within 1e-4 of transformers, about 58 tok/s decode |
| [ocean](ocean/) | 10.7 min | 217k | 76 | A- | B+ | A- | Tessendorf FFT ocean; the GPU FFT matches a CPU DFT to 2e-7; probably the wrong choppiness sign |
| [mandelbulb](mandelbulb/) | 7.7 min | 181k | 72 | A- | B+ | B+ | Mandelbulb and Mandelbox with shadows and AO; correct distance estimators; a weak "not black" check |
| [deferred](deferred/) | 15.2 min | 212k | 75 | B+ | B+ | B | 512 lights, tiled culling with a rigorous CPU-oracle check; 3 G-buffer passes, since std has no MRT |
| [sdftext](sdftext/) | 11.9 min | 206k | 69 | B+ | A- | B+ | SDF stroke font and an immediate-mode UI, best structure; a wrong K glyph and a stray line its own check missed |
| [sph](sph/) | 12.4 min | 230k | 69 | B | B+ | B+ | 102k particles; the GPU sort and scan exact against the CPU; the fluid is noisy and the "settles" claim weak |
| [physarum](physarum/) | 9.4 min | 174k | 59 | B | B+ | B+ | 1M agents at 0.5 ms a step; broken gain keys; one check tautological, the other physics-blind |
| [cloth](cloth/) | 16.2 min | 258k | 103 | B | B | B- | PBD cloth with every feature; a soft solver (27% stretch); the energy check passes through an off-by-one |
| [terrain](terrain/) | 18.2 min | 189k | 68 | B | B | B+ | Noise, LOD, shadow map, fog, water; a dummy colour target, since std has no depth-only pass |
| [windtunnel](windtunnel/) | 24.3 min | 275k | 88 | B- | B+ | A | A correct LBM; "no vortex shedding" came from a perfectly symmetric setup and short runs. At 30000 steps its own binary sheds at St 0.207 |

**Totals:**
- 2.33 M tokens, 849 tool calls, 2.8 agent-hours.
- 0 compiler crashes.
- 1 compiler soundness bug found (below).
- Every program builds with a plain `volec main.vl -o NAME` and passes its own tests.
- No program uses `unsafe`.
- Windowed runs hung for 5 of 10 agents (below).

## What the agents said about the tools

The counts come from the transcripts ([TOOL-STATS.md](TOOL-STATS.md), also in each README).

**Loved, by all ten: `volec check` after every edit (the hook).**
- It is sub-second and shows every error at once with an exact position and a `try:` line.
- Several agents never ran a failing build.
- `volec test` (the -O0/-O2 agreement), `guide` ("enough to write the whole program") and `query items/show/context` for std signatures (10–30 calls each) were the other well-used tools.

**Split: `fix --suggested`, applied automatically by the hook.**
- It saved real work: sdftext got 20 `&` call marks fixed in one step.
- It also made wrong edits in four runs:
  - ocean: a float `abs` became an integer `abs`, a silent truncation that made a check pass falsely;
  - cloth: a correct cast chain became a no-op;
  - deferred: it added an unrelated std-internal import, which is still in the file;
  - sdftext: a duplicate import.
- Files changed under the agents with only a "changed on disk" notice and no diff.

**Disliked, by all ten: the query-first hook.**
- It blocked 3–11 commands per agent (53 in all).
- It refused reads of the agents' own small files, which the Read tool reads anyway.
- On a compound command it refused the whole line without saying clearly that nothing on it ran. qwen35 lost "about a quarter of my turns", and one agent lost a file.

**Barely used:**
- `edit patch` (3 calls, one refused with `edit.breaks`), `refactor` (0), `explain` (0).
- `query grep` misses text inside strings, where the WGSL lives.
- `query show std::gpu::Color` found nothing.

## What the agents ran into in the language and std

1. **No float math in std.** Every agent wrote its own Taylor sin/cos and Newton sqrt, 25–40 lines each. The help on `x.sqrt()` suggested `fmt`.
2. **No `Gpa` in tests**, said by four agents. It's wrong: `#[test] fn t(gpa: Gpa)` works and is in `guide testing`. The error for `Gpa::default()` doesn't say so.
3. **Wrong or missing hints:**
   - `own.move_out` suggests `.clone()` for `Device` and `ComputePipeline`, which have none;
   - `parse_i64` gets the did-you-mean `parse_f64`;
   - `Named::Left` gets no suggestion;
   - a struct update `..f` gives a bare parse error;
   - a module and an item with the same name give "this import depends on itself";
   - an f-string passed as `[u8]` gives an `as_slice` error;
   - an `assert` on a call doesn't print the call's value;
   - the `const` hint offers `static` where `static` can't hold the value.
4. **std::gpu gaps:**
   - a pass has one colour target (no MRT for a G-buffer) and needs one even for a depth-only pass;
   - `gpu.layout` errors don't say which bindings the layout kept;
   - `gpu.usage` doesn't name the buffer;
   - the guide lacks WGSL atomics, one-module-per-kernel, compute-simulation patterns and the lifetime of `map_read` results.
5. **No multi-line strings or file embedding** for WGSL; `include_str` is named in a design doc but doesn't exist. Planned for 0.25.3.
6. **WGSL is checked only at run time.** Kept for 0.27, where WGSL becomes part of the language.

## Bugs found

- **Soundness:** an owned argument that can return early, passed to a call whose result is `?`'d (`f(make()?)?`), reaches the callee empty, at -O0 and -O2. Found by cloth; fix in progress.
- **Windowed `--frames N` runs never returned** for physarum, deferred, sdftext, terrain and qwen35's final build, and for examples/gpu/fluid2d. No frame events arrived; a hidden-window cause is suspected. A hung run held the GPU lock for its whole timeout. Fix in progress.
- **Query:** `query show` misses some std types.
- **Unused-import check:** an auto-added import shadowed by a parameter isn't flagged.

## What the reviews add

- **The agents' own checks are often weaker than they claim.**
  - Tautological checks: physarum's "inside", sph's "escape", cloth's "drag".
  - Checks that can't fail on the physics: physarum's balance, mandelbulb's "not black", terrain's noise range.
  - A check passing through an off-by-one: cloth's energy.
  - The agents then report these as verified. A short "a check must be able to fail" section in `guide testing` is cheap and would target this directly.
- **Honest failure reports were correct to be honest.** windtunnel said shedding didn't work and didn't fake it. The cause was the setup, not the code.
- **Borrowing was moderate.** Every agent modelled on examples/gpu/fluid2d. `snapshot_in`, `kernel`, `storage`, `run` and `verdict` were copied nearly verbatim in five projects. The domain code is original everywhere.

## Into 0.25.2.1

The tools, diagnostics, std math, the window hang, the soundness fix, std::gpu (MRT, depth-only passes, clearer errors) and the guide additions above. No WGSL checking and no new syntax, per the user. Round 2 runs the same ten tasks on 0.25.2.1 with the same brief, model and effort.

**Measures to compare:**
- hook blocks;
- failed tool calls;
- wrong auto-fixes;
- hand-written math lines;
- windowed runs that return;
- time and tokens;
- the three grades.
