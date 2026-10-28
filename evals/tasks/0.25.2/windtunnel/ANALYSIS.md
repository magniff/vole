# ANALYSIS: windtunnel (vole 0.25.2)

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note.

windtunnel (vole 0.25.2): the program works as a demo, but vortex shedding is NOT reproduced.

Files (all in /Users/magniff/workspace/tachyon/evals/tasks/0.25.2/windtunnel/): main.vl, sim.vl, shaders.vl, physics.vl, README.md, shot_speed.png, shot_vorticity.png, shot_dye.png. Build: `volec main.vl -o windtunnel` (ok). `volec check`: 0 errors. `volec test main.vl`: 4 passed.

## 1. Result

Works:
- Builds in about 0.9 s after edits; check clean; 4 CPU tests pass at -O0 and -O2.
- Window: 600 frames at 8 LBM steps a frame, about 120 fps (gpu-run, uncontended). Speed, vorticity, dye views; mouse draw/erase, keys, Reynolds control implemented. I did not view the live window; I checked via the offscreen --shot path and frame timing.
- Stable at default (Re 100, inflow 0.1, 400x240 cells): 12000 steps, all finite, largest speed 0.142 (expected centreline for a developed 0.1 mean profile).
- Mass, closed box, 1500 steps: total population sum 9.6e4, largest relative drift 2e-5 (float32 rounding of the lattice weights, about 1e-8/step, linear). Threshold 1e-4.
- Reynolds control reaches the collision: closed-box perturbation peak 0.042 decays to 0.037 at Re 240 but to 0.023 at Re 30.

Does not work:
- Vortex shedding not reproduced. At Re 100 the wake is steady and symmetric in the pictures; the probe's zero-crossing rate does not follow Re. Measured St (12000 steps, last 60%): Re 100 on 400x240: 0.55 (18 crossings, amplitude 0.004); Re 130: 1.0 (33 crossings, amp 0.003); Re 40: 0.43 (amp 0.004); empty channel: 0.99 (amp 0.0004, noise). On the earlier 400x160 grid (12.5% blockage), Re 100 gave 0.43. None near the textbook ~0.16-0.2. Cause not found.
- Re 160 and 200 (400x160) went NaN. Control capped at 140.
- The Strouhal line is reported as "NOT in 0.12..0.22" and is not in the exit status.

Verified by: --headless (closed box, channel, speed, finite); closed-box decay at --re 30 and 240 (cylinder-free build); --frames 600 with each --view and --shot; PNGs via ppm2png and read back.

## 2. How you worked

- Reads: `volec guide` (full), `guide gpu`, `guide window`, fluid2d main.vl and sim.vl, `volec query items`. About 8 reads.
- Code written with Write: shaders.vl (~300 lines WGSL), sim.vl (~380), physics.vl (~150), main.vl (~410). Lookups via `volec query items/refs`. Did not use `volec edit` for code changes.
- `volec check` ran after each edit via the hook; it caught real errors early. `volec fix --only unused` removed unused imports.
- Bash friction: the query-first hook blocked about 6 of my grep/tail/cat commands on .vl files, and blocked a Python script that edited .vl source; I used the Edit tool instead. `timeout` is not on this macOS shell. A `sleep` was blocked by the harness, so I polled in a loop instead.
- Debugging: a temporary column-mean printout (rho, ux per step). That was the most useful diagnostic: it showed density rising ~10% over 3000 steps.
- About 14 gpu-run invocations; waits 0-118 s (load 5-27).

## 3. What went well

- Pull-streaming LBM in WGSL, one shader per pipeline with per-shader bindings; `dev.shader_wgsl` plus `pipe.bind_layout(0)` made bind groups easy to match.
- Specific, quick `volec check` messages ("make it public", the constant-type error).
- The fluid2d example was a good model for the Sim/step/draw/snapshot layering.
- Sub-second builds; the test runner checks -O0 and -O2 agreement.

## 4. What went badly

- `error[type error] constant 'VIEWS' has type '[[u8]]'; constants must be integers, floats, bool or string literals`: the fix (a fn returning [u8]) is not in the message.
- `no method 'as_slice' on type 'Interp<closure(inout Fmt) -> () ...>'` when passing f"..." directly to a [u8] parameter; the fix is `format_in(f"...", gpa)`. Logged via agent-feedback.
- `'COLLIDE' is private | make it public`: shared shader constants are private by default; the hook's fix was right but surprising.
- `query items --root FILE` usage needed trial and error, and hook suggestions did not always fit.
- Missing guide text: no recipe for Zou-He or velocity-inlet boundaries in compute sims; no note on which mapped-buffer views may escape a function (`map_read` results cannot be returned; I had to copy into a Vec).
- Time sinks: outflow mass duplication (about 4 runs; copying all populations from the neighbour reads left-moving populations twice, so mass grows). Fixed with Zou-He inlet/outlet. Shedding search (about 8 runs, ~25 min of waiting) varying grid height, Re, probe location and run length without a clean wake.
- One `--frames 120` windowed run hung under gpu-run (killed at 60 s); 10 and 60 frames ran fine.
- No compiler, std or WGSL bug proven. Open question: whether the missing shedding is a kernel bug in mine or the physics of this under-resolved BGK setup (D=20 cells). Evidence against a collision bug: omega responds (decay test), empty channel is right, closed box conserves mass. Suspects left: probe placement, resolution.
- Where vole was harder than Rust/C: no const tables of slices (needs fn); mapped-buffer slices cannot be returned (copy needed); query-first hook makes reading short .vl files with shell tools costly.

## 5. The language

- Fought: const/static rules for tables; f-string into a [u8] argument; `pub` on shared shader constants; lifetime of `map_read` results. (Rust-style `&mut` was auto-fixed by the hook.)
- Liked: `inout self` methods on a Sim struct; `[HEAD, FUNCS, X][..]` concatenation of shader parts; `volec check` after each edit; `assert`-based tests; `format_in` with f-strings; `compute_pass(|pass| ...)` closures.

## 6. Suggestions (ranked by time saved)

1. Constant-of-non-literal-type error: suggest `static` or `fn` with the exact text (~2 turns saved).
2. Accept f"..." where [u8] is expected, or say "use format_in" (~2 turns).
3. Copy-free or documented lifetime for mapped-buffer slices, or a `map_read_copy_in(gpa)` (~1 debug cycle).
4. `guide gpu` section on compute-only simulations: ping-pong buffers, per-step uniform writes, readback for checks.
5. Let the query-first hook allow short own-file reads via tail/grep (it blocked ~6 commands).
6. A std helper to sum a buffer as f64 for conservation checks.
7. Document expected float32 conservation drift (~1e-8/step from weights) so tests use the right threshold.

Numbers: about 14 gpu-run runs, 4 compile-error rounds fixed by the hook, 1 outflow bug, 1 windowed hang.
