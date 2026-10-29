# windtunnel: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

What works: a D2Q9 BGK-type lattice Boltzmann flow on GPU (640x320 cells, cylinder 40 cells across, inflow 0.08 lattice units). Pull-streaming and regularized collision in one kernel, a dye kernel, a probe kernel, a render kernel with speed / vorticity / dye views. Windowed mode: drag left to draw obstacles, right to erase, `[` `]` brush size, `c` clear, `r` reset, space pause, `v`/`1`-`3` views, `+`/`-` Reynolds number (20 to 250, changes only the relaxation rate), `q` quit. Title bar shows Re, view, pause.

Verified (all through gpu-run, load 2-3, waits 0.0 s):
- `./windtunnel --headless --check` exits 0: closed-box mass over 1000 steps drifts 2.2e-5 relative (threshold 1e-4); Strouhal number 0.168 over the second half of 40000 steps (threshold 0.14-0.20; known about 0.165 at Re 100); finite everywhere, max speed 0.113 (limit 0.577).
- Re 150, 200, 250: also shed and stay finite (St 0.183, 0.191, 0.191). Re 60: no shedding (steady wake), plausible at 12.5% blockage with plug inflow.
- Pictures (converted to PNG and read): speed wake, vorticity vortex street, dye bands following the wake.
- `--frames 60` and `--frames 120` windowed runs: no crash, shot written. I could NOT watch the window (the tool said "no frame in 3 s ... display asleep"), and mouse painting was never exercised. Treat interactive behaviour as untested.
- Not verified: lift/drag, the mouse path, anything above Re 250.

Mass: the scheme conserves mass exactly in exact arithmetic (collision conserves it; bounce-back and streaming permute populations). The 2.2e-5 residual is float32 round-off; I did not separate it out.

## 2. How you worked

Commands, roughly: `volec guide` (full read, ~2k tokens), `guide gpu` (once), `guide testing` (once, for the gpa-in-test rule), `query items std::gpu`/`std::window` (once, large output, not useful), `query show` on 2 items, `guide --find` (no use). About 12 `volec main.vl -o` builds, about 8 `check`/`fmt`/`test`/`fix --only unused` runs. About 25 headless runs through gpu-run. Never used: `query context`, `query refs`, `edit patch`, `refactor`, `probe`, `reduce`, `debug`, `fix --suggested`. I edited with the file tools and Python (the query-first hook never blocked me, since I edited files, not compiler source). One Bash `sed -i` failed oddly with "sed: -e: No such file or directory" and I switched to the Edit tool.

Helped: check-after-edit hook (it auto-fixed a missing `&` on an inout call and printed the error with its `try:` line); `volec fmt`; `volec test` with its -O0/-O2 agreement; the own.move_out help text (it told me the exact options).
Did not help: the physics debugging, which had no tool support. I used headless series dumps and a Python script without numpy (`python3 -I`) for the spectrum.

Turns and attempts on the hard problems:
- Strouhal: 0.316 at D=25, still 0.316 at D=40, then 0.50 after a collision change. Cause: my analysis window started at n/3, so it counted the start-up transient (crossings about 260 steps apart until about step 14000). Changing to n/2 and 40000 steps gave 0.168. About 6 headless runs plus manual crossing analysis.
- Blow-up at Re 150 (non-finite near step 20500): I tried D=40 (no fix), a regularized collision (no fix), then a zero-gradient outlet copying from the neighbour instead of the cell's own stale population (fixed). The probe series showed the growth first.
- Dye: bilinear semi-Lagrangian smeared the bands before the cylinder. Catmull-Rom sampling fixed most of it.

## 3. What went well

- The WGSL compiled first time, including const arrays of array<i32,9>, runtime indexing of const arrays and vec4, arrayLength, and loops inside kernels. The WGSL-to-Metal path worked, and no shader compile error came up.
- The check errors are specific and carry `help:` and `try:` lines (own.readonly named the exact `var` fix).
- `volec test` runs -O0 and -O2 and checks the test allocator (the gpa-taking test form is in the guide).
- The window API (set_title, Mouse in physical pixels, Logical keys) was easy to find via `query show`.
- fluid2d as a reference was the right model; I read main.vl, sim.vl and the header of shaders.vl and it was enough.

## 4. What went badly

- "own.move_out: cannot move 'self.g_lbm0' (BindGroup) out of a reference ... BindGroup has no Default to leave in its place (no 'std::take') and no '.clone()'". I wrote `let (l0, l1) = (self.g_lbm0, self.g_lbm1);` to capture handles for a closure. Fix: put `self.g_x` directly inside each branch. This took 2 rewrites of `record` and `draw`.
- "own.move_out: cannot move 'self.f0' (Buffer) out of a reference ... an `if` or `match` that picks 'self.f0' moves it out". Same root cause: `if self.cur == 0 { self.f0 } else { self.f1 }` (my `cur_f` helper) is a move. Fix: per-branch code.
- "own.readonly: 'fb.map_read(self.dev)' changes 'fb', a let binding: it is read-only" — map_read counts as a change to the buffer. Clear fix, but surprising.
- Interactive runs: "window: no frame in 3 s: the window is occluded or not shown (the display is asleep); frames come 10 a second until it shows" — printed during a run that still went on to write the shot. I could not tell whether frames were delivered normally.
- The guide's compute example uses a fixed workgroup and one dispatch; for a kernel per step inside one encoder with a parity swap, I had to reconstruct the pattern from fluid2d's sim.vl. The guide has no section on ping-pong buffers.
- The `query items std::gpu` output is huge (170+ lines) with no filter for "what do I need to make a buffer".
- Per-step GPU control: the uniform holds one step index, so recording many steps in one encoder cannot change per-step parameters. The headless probe forced one submit per step (40000 submits). It is the main cost in the headless run (about 13 s wall for 40000 + 1000 steps incl. readbacks; this is wall time, not GPU time).
- In the first version I had no f32 readback helper for the probe. `probe_series` reads the whole buffer each time; fine here, but not obvious.

## 5. The language

Fought me: move-only handles (Buffer, BindGroup) inside `inout self` methods and closures; `&` on inout calls (fixed by the hook, but the error needed reading); `if`-expressions and f-strings nested (`f"...{if p { ", paused" } else { "" }}"` compiled, which is good, but a reader would not guess it).
Liked: f-string format specs (`{re:.0}`, `{cfg.omega:.4}`, `{v:.7e}`); `#[pure]`; `Vec::filled_in`; `select` and `clamp`; the test gpa form; checked indexing (no off-by-one slipped through into a crash; a bad probe index would have been caught).
Not tested: whether `f64::is_finite` exists (I used `x - x != 0.0` for NaN checks).

## 6. Suggestions, ranked by time saved

1. Let a step-dependent value be data, not a uniform: an array of per-step parameters (or a step-index buffer per dispatch) so one encoder can record many steps. This removes the one-submit-per-step cost and simplifies probe/series work for any time-stepped GPU code.
2. Make GPU handles (Buffer, BindGroup, pipelines) cheap to capture, e.g. Copy or a borrowed handle usable in closures, or allow `self.field` as a let argument inside a closure without a branch. About 3 turns lost to move_out.
3. A GPU ping-pong pattern in the guide: two buffers, two bind groups, a parity field, dispatches in one pass.
4. Document that `map_read` on a `let` buffer makes it `var`, or make the error say so in the first line.
5. Clarify the window "no frame in 3 s" message: say whether frames are still being delivered and whether the program will exit.
6. Filter `query items` output (kind, name, one line), or add `query items --names`.
7. A physics note in the guide or examples: BGK at tau near 0.5 blows up without a regularized collision or a good outlet; I lost about 4 runs to this.
Attempts: Strouhal 4 headless runs plus analysis; Re 150 blow-up 3 fixes; dye 2 changes; overall about 25 headless runs.
