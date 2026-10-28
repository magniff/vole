# windtunnel: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

(ANALYSIS.md could not be written: the harness refused the file write. This is the full analysis, for the orchestrator to save verbatim.)

## 1. Result

**Works:** a D2Q9 BGK lattice-Boltzmann wind tunnel on std::gpu (WGSL, Metal), 480 x 240 cells, a 24-cell cylinder, inflow from the left, outflow on the right. Four views (speed, vorticity, dye, pressure), mouse draw and erase, a Reynolds-number control, pause, reset, clear and cylinder restore. `volec main.vl -o windtunnel` builds. `volec test main.vl`: 7 tests pass at -O0 and -O2.

**Headless checks** (`./windtunnel --headless`, through gpu-run, default Re 100):
- Mass, closed box, 3000 steps: fluid density total 114759.000 at start, 114761.759 at 1500, 114764.399 at 3000. Relative drift 4.7e-5 (1.8e-3 per step). The check passes at 1e-4. The claim that this is float32 rounding and not a scheme leak is an argument; I did not measure the rounding directly.
- Shedding, open channel, 6000 transient steps then 12000 samples of the vertical speed 2D behind the cylinder: Strouhal 0.163 (published about 0.164 at Re 100). Peak-to-peak 0.12 in lattice units (about 0.6 U). Not checked against a reference amplitude.
- Re 60: Strouhal 0.160. Re 90: Strouhal 0.162. Re 30: no shedding, as expected.
- Pictures: `shot.png` (dye) shows a Karman street; `vorticity.png` shows alternating shear layers.

**Does not work / not verified:**
- **Stability ceiling.** Re 110, 120, 135, 150, 200 and 250 all blow up (probe amplitude far above the inflow speed). Re 100 with a 32-cell cylinder also blows up. The Reynolds control is therefore capped at 100 (`--re` above 100 is refused; the `+` key stops there). This is a real limit of my BGK setup on this grid. I did not find the cause, and did not try a regularised or MRT collision or a finer grid.
- **Windowed controls not exercised.** The window was occluded during my runs, so `--frames 60` reported 101 ms a frame from the occlusion timer, not GPU time. I did not drive the mouse, the keys or the Reynolds changes in the window. The step code is shared with the headless path; the input code is compiled but unrun.
- **Zero-output moments kernel (unresolved).** I first computed fluid mass with a separate compute kernel (read-only storage f in, density out). On the first call, before any step, it returned zeros for every cell, on two calls in a row. Later readings were non-zero, but those may have come from the collide kernel, which writes the same output buffer. I replaced it with a CPU sum of a readback, and the check then read the right initial value (114759). I could not establish the cause and did not minimise a repro. This is a suspicion, not a finding about std::gpu.

## 2. How you worked

- **Commands:** `volec guide` (full read), `volec guide gpu`, `volec guide window`, `volec guide testing`, `volec guide --find` (3 uses); `volec check main.vl` (about 20 runs, mostly via the hook); `volec test main.vl` (4); `volec main.vl -o windtunnel` (about 9 builds, including debug copies); headless and windowed runs through `gpu-run` (about 12); `volec edit patch` (1 attempt, one replacement did not apply, then Edit); `tools/agent-feedback` (3 records).
- **Query tools: none.** I never ran `volec query context`, `query show`, `query refs`, `edit replace` or `fix --suggested`. I read the fluid2d reference with `cat` and `sed -n`, and wrote files whole. That was my choice, so I cannot say whether query would have saved time. I suspect it would have helped most in the GPU module, where the error lines were right and the fix was the part I had to work out by reading.
- **Hooks:** the check hook printed the errors after each Edit, which saved a step each time and was the most useful part of the loop. The `volec fix` hook applied the `&` for an inout call on its own (one line, reported), and that was right. The query-first hook never blocked me. A plain `sed -i` on a `.vl` file failed with a confusing error (`sed: 1: "lattice.vl ... extra characters`), so I used Edit for every later change.
- **Turns (approximate):** about 9 on the GPU module's move-out errors, about 10 on the mass-check zero (unresolved), about 4 on the stability sweep, about 6 on constant and type fixes. Compile errors across the program: about 25, about 14 of them in the GPU module.

## 3. What went well

- Compiler checks are fast and precise: file, line, column, and often an exact `try:` line. The automatic `&` fix for inout calls was right.
- The WGSL compiled first time for all five compute kernels and the render pipeline. The bind-group numbers matched the shaders' `@binding` numbers with no reflection errors at pipeline creation.
- `volec test` runs tests at -O0 and -O2 and checks they agree.
- The fluid2d example was a good model for the GPU setup (device, buffers, bind groups, headless PPM snapshot). Copying its shape, not its text, got a first working kernel quickly.
- The shedding check worked first time with a probe and a zero-crossing estimator. Strouhal came out at the published value.

## 4. What went badly

- **Move-only handles in `if` expressions.** `let gc = if k == 0 { self.g_collide0 } else { self.g_collide1 };` gave `error[own.move_out] cannot move 'self.g_collide0' (BindGroup) out of a reference: what it points to keeps its value`, with the suggested fix `std::take(&self.g_collide0)`. That fix would have removed the bind group from `self` and broken the next step. The right fix was to dispatch inside each branch of the closure. The help does not say that choosing between two fields with `if` moves them. The same happened to a `Buffer`, again with a `take` suggestion. Ten such errors in one file; about 9 turns.
- **Let/var/inout surprises.** `error[own.readonly] ... 'f.map_read(...)' changes 'f', a let binding`: mapping a buffer counts as a change, so it needs `var`, and a helper that maps it needs an `inout` parameter. The help was clear once I had the rule.
- **Constants.** `const VIEWS: [[u8]] = [...]` failed with "constants must be integers, floats, bool or string literals"; the help points to `static`. I replaced it with an if-chain function and did not test `static`.
- **Integer literal types.** `let value = if inp.left { 1 } else { 0 };` was inferred `i64` and then rejected where `u32` was needed (`expected 'u32', got 'i64'`). The fix is trivial, but the literal's type is not visible at the call site.
- **parse_int return type.** `match parse_int(...) { Some(n) => ... }` gave `expected 'Result<i64, ParseIntError>', got a pattern of 'Option'`. `unwrap_or(0)` works; the guide's parse_int line does not state the return type.
- **Shaders as strings.** Each WGSL line needs `\n\`. A mistake would show up as a shader error, not a string error. I did not test a deliberately bad shader, so I cannot say what that error looks like.
- **Debug round trip.** Finding the zero reading took about 5 builds and 4 GPU runs and did not settle the cause.
- **Silent wrong values.** The zero-output moments kernel produced no error. The mass check printed `relative drift inf` with no hint of where the zero came from.
- **No display, so no window check.** The interactive path is the least-checked part.

## 5. The language

- **Ownership of GPU handles** is the biggest friction. `BindGroup` and `Buffer` are move-only. Every reuse through a field must be written inside the closure or as a plain argument, and the error suggests `take` as the first fix, which is wrong for handles. Copy handles, or a clear rule for passing a field to a function, would remove most of it.
- **Closures and `self`.** `enc.compute_pass(|pass| { ... self.g ... })` works, but only when the group is an argument inside the closure, not a `let` outside.
- **Types.** Integer literals default to `i64` in a way that surprises in `u32` contexts; float literals are `f64` (`Vec::filled_in(n, 0.0, gpa)` needed an annotation for `f32`). Both are reported clearly, but they cost turns.
- **What I liked:** `inout` at the call site (`&mask`) makes the mutation visible, and the compiler names it when you forget. Tests beside the code, with -O0 and -O2 agreeing, is a good habit. The `std::gpu` shape (device, buffers, bind groups, encoder, closures per pass) is clean and maps well onto WGSL.

## 6. Suggestions, ranked by time saved

1. Make the move-out help right: for a handle used through `if` or a field, say "a handle is not Copy: call the function inside each branch", not `std::take`, which silently removes the bind group from `self`. This cost the most time.
2. Make `BindGroup` and `Buffer` cheap to pass (Copy handles, or a borrow form that `run(&pass, ...)` can use without a move), or document the one pattern that works in `std::gpu`.
3. Name the bind-group/shader mismatch: when a shader binding is missing from a bind group, give the name and number. I did not hit it, but expect it is the next common error.
4. Show the return type in the parse help: `parse_int` returns `Result`; the guide example should say so.
5. A GPU test mode in volec: a headless kernel run compared with a CPU reference would have caught the zero-output problem in one run.
6. Document the WGSL error path: what a bad line looks like, with its line number, when the shader is compiled at pipeline creation.
7. Say when `if` expressions move; a guide line near "owned values" would have saved about 9 turns.

**Files** (`/Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/windtunnel/`): `main.vl`, `lattice.vl`, `shaders.vl`, `sim.vl`, `README.md`, `shot.png`, `vorticity.png`, `vorticity.ppm`, `windtunnel` (binary). The ANALYSIS.md write was refused; this text is its content.

**Reproduce:** `volec main.vl -o windtunnel && evals/tasks/0.25.2.1/tools/gpu-run --timeout 280 -- ./windtunnel --headless --shot shot.ppm` (checks pass; exit 0). `volec test main.vl` (7 pass). Agent-feedback recorded 3 lines (move-out help, moments zero output, sed on .vl).
