# physarum: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

Works:
- Simulation: 1,048,576 agents (default) on a 960x540 trail. Each agent senses left/centre/right, turns by a Jones-style rule (straight when centre is strongest, random turn when weakest, else toward the stronger side), moves, bounces off walls, and deposits with atomicAdd into a fixed-point grid (256 units to a unit). A diffusion compute pass (clamped 3x3 mean mixed in by `diffuse`, plus deposits, times `keep`) writes the other of two ping-ponged trail grids and clears the deposits. A render pass draws the trail through 1-exp(-t*gain) on a blue-to-cream ramp.
- Headless (`--headless --steps N --every K --shot FILE.ppm`): prints the trail total at each check, its prediction, agents outside, steady state, ms per step, two verdicts, then writes the shot.
- Window: keys for sensor angle, sensor distance, turn, decay, diffusion, pause, reset, quit; mouse left adds food, right repels.
- Tests: `volec test main.vl`, 5 passed at -O0 and -O2.

Verified (GPU runs through gpu-run):
- `volec main.vl -o physarum`: built.
- `volec test main.vl`: 5 passed.
- `gpu-run -- ./physarum --headless --agents 65536 --steps 200 --every 50`: both verdicts ok; total vs prediction off by about 5e-8 at each check.
- `gpu-run -- ./physarum --headless --steps 600 --every 300 --shot shot.ppm`: 1M agents, both verdicts ok, total 2402304.7 vs steady state 2402304.5 (0.0000% off), 0 agents outside, 0.53 ms a step. shot.png shows branching networks.
- `gpu-run --timeout 60 -- ./physarum --frames 120`: window ran 120 frames and quit by itself. It reported the window was occluded or the display asleep, so 101 ms a frame (9.8 fps) is display pacing, not the simulation (about 0.5 ms a step).

Not verified: the mouse (food/repel) and the keys. They compile, but I did not drive them with input, and the window-to-cell mapping is copied from fluid2d's pattern without being exercised.

## 2. How you worked

- `volec guide` once (core, about 2k tokens) and `volec guide gpu` twice. The gpu guide was the main learning cost (about 20k+ characters read in pieces).
- Reference reads: `sed -n` on examples/gpu/fluid2d (main.vl, sim.vl's new_in, snapshot_in and helpers), as plain text. The hook allowed it. I did not open life, galaxy, pathtrace or voxel.
- One blocked command: `grep -rl "atomic<" examples compiler/std tests`, refused because it touched compiler/std .vl. Recovered with `volec query grep 'atomic<' --count` (5 hits), which worked. The block message named the alternative.
- `volec check` hook: 1 real error (`unknown module 'gpu'`, fixed by adding `use std::gpu;`) and 1 mechanical fix (`*p` changed to `p`). Useful, not in the way.
- `volec query`, `volec edit`, `volec refactor`: not used. Files were written whole; edits were one-line sed changes checked by grep.
- `gpu-run`: 5 runs, each waited 0.0 s, load 2.2 to 3.2.
- Turns lost: the WGSL name clash took 2 turns (run, read error, rename); the unknown-module error took 1 turn.

## 3. What went well

- Close to fluid2d, so the structure (Sim struct, pipelines, bind groups, frame function, snapshot) was copied and changed; one pass to write.
- The 0.25.2.2 per-entry-point bind-group layout let one WGSL text serve two kernels (INIT has `init` and `clear`): each pipeline's bind group lists only its own bindings, and the compiler accepted it.
- The check hook caught my one real compile error and fixed the `*p` spelling without a turn.
- The closed-form check works because the clamped 3x3 mean conserves mass and decay is multiplicative: total after each step = keep*(total + deposits). The GPU matched to about 5e-8 relative, which tests the atomics, ping-pong and clear, and costs only the trail sum per check.
- Whole-program build about 0.3 s wall.

## 4. What went badly

- WGSL errors appear only at run time. My shader had entry point `fn agents` and storage binding `var<storage> agents`. `volec check` and the build passed; the run failed: `physarum: gpu: the shader did not compile: 31:4: error wgsl.redefined: 'agents' is declared twice at module scope`. Minimal repro: one `shader_wgsl` string with an entry point and a binding of the same name. Fix: rename the entry point. Compile-time checking of the WGSL string would catch this before a run.
- `error[type error] unknown module 'gpu'` after `use std::gpu::{RawSurface, Surface};` and then `gpu::Instance::new_in`. Adding `use std::gpu;` fixed it. I expected one item's `use` to bring the module name, as in Rust. I did not check `volec explain` for this code.
- WGSL as a backslash-newline string: each line ends `\n\`. Works and the guide shows it, but a 160-line shader in this style is hard to read and to edit with sed. The planned wgsl{} form (0.27) would fix it.
- Two shader modules from one text: I compiled the INIT text twice, one per pipeline, because I assumed `compute_pipeline` takes its `Shader` by value. I did not verify that; the docs I read do not say whether one shader can back two pipelines.
- No CPU-side test of the kernels. The headless check is the only test of the WGSL, and it needs the GPU lock. `volec test` covers only packing and the closed-form recursion.
- Fifteen keys as an if/else-if chain on `c == 'r' as u32` is verbose. I did not test whether a `match` on char literals works, so I cannot say whether it is a gap.
- The window's pacing notice when the display is asleep: the frame time printed (101 ms) looks like simulation cost unless you read the notice.

## 5. The language

Fought me:
- The gpu guide is long; reading the needed sections was time, not a blocker.
- WGSL atomics: `array<atomic<u32>>` must be `read_write` even for reads. The guide says so; I followed it.
- Float-to-u32 cell indices need clamping by hand in WGSL. A helper would be common.
- No undefined behaviour or checked-index failures hit; integer wrap in the hash worked.

Liked:
- `let (dev, var queue) = inst.adapter()?.device()?;` and the pipeline/bind-group pattern are short once copied.
- `#[test]` with `assert_eq` on f32 worked as written.
- The `unknown module` error was clear enough to fix at once; check after each write gave fast feedback.

## 6. Suggestions, ranked by time saved

1. Check WGSL inside `volec check` (at least entry-point and binding names, and parse) so `wgsl.redefined` appears before a run. This was the one real time sink: 2 turns and a failed run.
2. A raw multi-line string for WGSL (the 0.27 wgsl{} plan). The `\n\` style costs care on every edit.
3. Make `use std::gpu::X` also bring `gpu` into scope, or name the fix in the `unknown module` error (`add use std::gpu;`).
4. State in the gpu guide whether one `Shader` can back two pipelines.
5. A way to run one WGSL kernel on the CPU, or a CPU-side test helper for kernel logic, so the rule can be tested without the GPU lock.
6. A notice in the window's output when the display is asleep, saying the frame time is pacing.

Numbers: 3 successful builds; 1 failed run (WGSL, 2 turns); 1 `volec check` error (1 turn); 1 mechanical hook fix; 5 gpu-run calls, all waited 0.0 s; 2 agent-feedback lines; 0 `volec query`/`edit` calls.
