# physarum: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result
Works:
- `volec main.vl -o physarum` builds; `volec check` clean; `volec test main.vl`: 5 passed (-O0 and -O2 agree).
- Headless (default 1,048,576 agents, 1024 map, 300 steps, via gpu-run): trail total follows T' = (1 - decay)(T + agents) at every check, worst relative error 2.5e-7 (CPU f64 sum of the GPU trail); 1048576 of 1048576 agents inside the map. Output: `worst rel err 2.5e-7: ok`, `1048576 of 1048576 inside the map: ok`.
- Largest allowed (4,194,240 agents, 2048 map, 1000 steps): trail check ok (2.4e-7), all agents inside.
- shot.png (300 steps) shows a developed network: loops, junctions, thin tubes, no seams at the edges.
- Windowed `./physarum --frames 120 --shot win.ppm` runs to the end and writes a frame. The display was asleep, so frames came from the 10 fps timer.

Not verified: the keys and mouse compile and use the same Tune::adjust / Pointer code as headless, but I did not drive them with real input or see the window; window frame times not measured.

Timings (gpu-run, including check read-backs): ~0.65 ms a step over 1000 steps at 1M/1024; ~5.4 ms a step at 4.2M/2048.

A real bug found by looking: an early hash (additive-linear) gave diagonal bands from step 5. The early-step picture and a heading check (mean resultant length after reset 0.0012 vs ~0.0010 for uniform) pointed at it; replaced with lowbias32 applied twice. The mass check passed either way, so conservation alone cannot catch a spatially wrong but mass-conserving pattern.

## 2. How you worked
- `volec guide` (core), `guide gpu` (read in full, plus fluid2d main.vl and sim.vl), `guide window`: about 4 reads.
- `volec query show` for std signatures: 6 calls; `query items std::window`: 1. `query show std::window::Surface::frame` said "no definition". I did not use context, refs, edit patch/replace, refactor or fix. I wrote files with Write, Edit and Python/sed.
- The check hook ran after edits about 6 times with errors; each had a correct `try:` line. Helpful for catching type errors at once; I fixed by hand.
- query-first.py blocked one grep over compiler/std (as intended).
- volec test: 2 runs. gpu-run: about 12 runs; load 2.2 to 3.3; never waited more than 0.0 s. ppm2png: 6 runs, PNGs read visually.
- About 6 successful builds (each under 1 s); about 4 check runs failed before a clean one.
- Turns on problems: bands ~6 turns; 2048 dispatch limit ~3 turns; exposure 2 turns.
- Tools recorded via agent-feedback: 3 lines.

## 3. What went well
- The GPU API is pleasant: a Sim struct holding buffers, pipelines and bind groups per ping-pong parity; one method per step; `enc.compute_pass(|pass| ...)` closures over self.k_... were easy to copy from fluid2d.
- One shader module per kernel worked as the guide says: CLEAR has one binding, INIT two; layouts matched first try.
- check error messages carried exact try: lines (own.readonly "declare it var"; the f64 one "d: f32" or "d as f32").
- The exact mass-conservation check exercises atomics, both trail buffers, decay and the blur; agreement to 2e-7 first time gave confidence in the wiring.
- gpu::f32s on a mapped buffer and f64 sums were simple.

## 4. What went badly
- Runtime-only error with an internal name: `sim.vl:166:13: gpu.limits: workgroups per dimension: x = 65536, self.max_groups = 65535`. The check passed; it appeared only in a headless run. Fix: 256-wide workgroup for the clear kernel and a map cap of 2048. The message should name the limit and the call, and ideally be a check-time error when the count is derivable from constants.
- `own.move_out: cannot move 'self.trail_a' (Buffer) out of a reference`. The suggested fix `std::take(&self.trail_a)` is wrong for a GPU buffer (not applied). I used two explicit branches. The help does not explain that a field of inout self can be read through a method or passed by value only within each branch.
- `undefined variable 'cos'` with `help: add use std::math::cos;`. The guide says float math is methods; I used h.cos(), which worked.
- `expected 'f32', got 'f64'`: `let d = if dir > 0 { 1.0 } else { -1.0 };` used with f32 gives the error at the use, not at the literal. Fix `let d: f32 =`.
- `query show std::window::Surface::frame`: "no definition"; its try: lines pointed at other agents' folders (evals/tasks/0.25.2/...). I used the examples' code instead.
- My mistake: `sed -i 's/.../' file` on macOS needs `-i ''`; switched to Python.
- Window: the display was asleep so `--frames` ran on the 10 fps timer, as documented. Windowed checks cannot show frame times or the picture. A standard window/gpu snapshot helper (render to texture, PPM) would have helped; I wrote my own.
- The draw method takes self by value while the headless snapshot takes inout self; both compiled. I copied fluid2d's pattern without understanding why by-value draw is allowed on an inout receiver.
- The atomic storage rule: I used read_write for the diffuse kernel's atomic deposit buffer even for loads, to be safe. A note in the guide's atomics section would settle it.

## 5. The language
Fought me:
- Ownership of GPU handles inside inout self: a buffer cannot be moved out of a field, so `if c { self.a } else { self.b }` yielding a buffer is an error; two branches fix it. Correct, but hit twice.
- Float literals default to f64 and do not narrow; with f32 GPU code I added several `as f32` or `: f32`.
- Closures capturing self in compute_pass worked without fuss; inout on the struct kept pipelines and bind groups in one place.

Liked:
- The check hook's specific errors with concrete try: lines, right after each edit.
- WGSL as plain strings in .vl files joined into one module per kernel: readable; WGSL errors carry locations.
- volec test runs CPU tests at -O0 and -O2 and checks agreement.
- The gpu.limits check exists at all: it caught a real limit.

## 6. Suggestions, ranked by time saved
1. Check dispatch counts against dev.limits() when derivable from constants, and name the limit (not self.max_groups). Cost 3 turns and a headless run.
2. For inout self and GPU-handle fields, explain in the error that each if-branch must move its own field, with an example. Cost 2 turns.
3. Float-math help should suggest the method form (h.cos()) when a free cos is undefined. Cost 1 turn.
4. Document the atomic storage access rule (read_write even for atomicLoad) in the gpu guide, with the reason.
5. A window/gpu snapshot helper (render to texture, PPM) for headless and short windowed runs.
6. query show should resolve std::window Surface methods, or say which type has them; the try: lines pointed at other agents' folders.
7. The guide should say whether std::math has free functions or only methods.
